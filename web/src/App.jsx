import { useState, useEffect, useRef, createContext, useContext, useMemo } from 'react';
import { Routes, Route, NavLink, Link, Navigate, Outlet, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { LayoutDashboard, Car, CalendarCheck, Sparkles, UserCircle, LogOut, MessageSquare, Menu, X, Filter, ChevronLeft, ChevronRight, ArrowLeft, Check, AlertCircle, Send, User, Loader2, Wrench, Clock, TrendingDown, Gauge, Mail, Phone, MapPin, ArrowUp, ArrowDown, RotateCcw, Gift } from 'lucide-react';
import { format, parseISO, formatDistanceToNow, addDays, addMonths, startOfMonth, endOfMonth, startOfWeek, endOfWeek, eachDayOfInterval, isSameMonth, isSameDay, isBefore, startOfDay } from 'date-fns';

// ============================================================================
// API CLIENT
// ============================================================================
const BASE = import.meta.env.VITE_API_URL || '';
class ApiError extends Error { constructor(status, body) { super(body?.message || body?.error || `HTTP ${status}`); this.status = status; this.body = body; } }
async function request(method, path, { body, params } = {}) {
  const url = new URL(`${BASE}${path}`, window.location.origin);
  if (params) for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== null && v !== '') url.searchParams.set(k, v);
  const headers = { 'Content-Type': 'application/json' };
  const token = localStorage.getItem('fs_token');
  if (token) headers['Authorization'] = `Bearer ${token}`;
  const res = await fetch(url.toString(), { method, headers, body: body ? JSON.stringify(body) : undefined });
  const parsed = res.headers.get('content-type')?.includes('application/json') ? await res.json() : null;
  if (!res.ok) throw new ApiError(res.status, parsed);
  return parsed;
}
const api = {
  getAuthToken: (memberId) => request('POST', '/v1/auth/token', { body: { member_id: memberId } }),
  getAuthMe: () => request('GET', '/v1/auth/me'),
  listMembers: (params) => request('GET', '/v1/members', { params }),
  getMember: (id) => request('GET', `/v1/members/${id}`),
  getMemberSubscription: (id) => request('GET', `/v1/members/${id}/subscription`),
  getMemberReservations: (id) => request('GET', `/v1/members/${id}/reservations`),
  getMemberPointHistory: (id) => request('GET', `/v1/members/${id}/point-history`),
  listFleet: (params) => request('GET', '/v1/fleet', { params }),
  getVehicle: (id) => request('GET', `/v1/fleet/${id}`),
  getAvailability: (id, from, to) => request('GET', `/v1/fleet/${id}/availability`, { params: { from, to } }),
  listTiers: () => request('GET', '/v1/tiers'),
  quoteReservation: (data) => request('POST', '/v1/reservations/_/quote', { body: data }),
  createReservation: (data) => request('POST', '/v1/reservations', { body: data }),
  confirmQuoteReservation: (data) => request('POST', '/v1/reservations/confirm-quote', { body: data }),
  cancelReservation: (id, reason) => request('POST', `/v1/reservations/${id}/cancel`, { body: { reason } }),
  conciergeChat: (data) => request('POST', '/v1/concierge/chat', { body: data }),
};

// ============================================================================
// AUTH CONTEXT
// ============================================================================
const AuthContext = createContext(null);
function AuthProvider({ children }) {
  const [member, setMember] = useState(null);
  const [subscription, setSubscription] = useState(null);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    const token = localStorage.getItem('fs_token');
    const memberId = localStorage.getItem('fs_member_id');
    if (!token || !memberId) { setLoading(false); return; }
    Promise.all([api.getMember(memberId).catch(() => null), api.getMemberSubscription(memberId).catch(() => null)])
      .then(([m, s]) => { setMember(m?.member ?? null); setSubscription(s?.active_subscription ?? null); })
      .finally(() => setLoading(false));
  }, []);
  const signInAs = async (memberId) => {
    setLoading(true);
    try {
      const authRes = await api.getAuthToken(memberId);
      localStorage.setItem('fs_token', authRes.token);
      localStorage.setItem('fs_member_id', memberId);
      const subRes = await api.getMemberSubscription(memberId).catch(() => null);
      setMember(authRes.member);
      setSubscription(subRes?.active_subscription ?? null);
    } catch (err) {
      alert(`Sign in failed: ${err.message}`);
    } finally {
      setLoading(false);
    }
  };
  const signOut = () => {
    localStorage.removeItem('fs_token');
    localStorage.removeItem('fs_member_id');
    setMember(null);
    setSubscription(null);
  };
  const refreshSubscription = async () => {
    if (!member) return;
    const s = await api.getMemberSubscription(member.id);
    setSubscription(s.active_subscription);
  };
  return <AuthContext.Provider value={{ member, subscription, loading, signInAs, signOut, refreshSubscription }}>{children}</AuthContext.Provider>;
}
const useAuth = () => useContext(AuthContext);

// ============================================================================
// SHARED UI
// ============================================================================
const TIER_STYLES = { 1: 'bg-slate-100 text-slate-700', 2: 'bg-navy-50 text-navy-700 border border-navy-100', 3: 'bg-cream-200 text-slate-800 border border-slate-200', 4: 'bg-gold-50 text-gold-600 border border-gold-100', 5: 'bg-burgundy-50 text-burgundy-700 border border-burgundy-100' };
const TierBadge = ({ tier, className = '' }) => <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-semibold ${TIER_STYLES[tier] || TIER_STYLES[3]} ${className}`}>TIER {tier}</span>;
const STATUS_STYLES = { available: 'bg-emerald-50 text-emerald-700 border border-emerald-100', reserved: 'bg-amber-50 text-amber-700 border border-amber-100', in_use: 'bg-sky-50 text-sky-700 border border-sky-100', maintenance: 'bg-slate-100 text-slate-700', detailing: 'bg-slate-100 text-slate-700', confirmed: 'bg-emerald-50 text-emerald-700 border border-emerald-100', requested: 'bg-amber-50 text-amber-700 border border-amber-100', picked_up: 'bg-sky-50 text-sky-700 border border-sky-100', returned: 'bg-slate-100 text-slate-700', cancelled: 'bg-rose-50 text-rose-700 border border-rose-100', active: 'bg-emerald-50 text-emerald-700 border border-emerald-100' };
const StatusPill = ({ status }) => <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium capitalize ${STATUS_STYLES[status] || 'bg-slate-100 text-slate-700'}`}>{status?.replace(/_/g, ' ')}</span>;
const Spinner = ({ className = 'w-5 h-5' }) => <Loader2 className={`animate-spin ${className}`} />;
const PageHeader = ({ title, subtitle, action }) => (
  <div className="flex items-start justify-between mb-8 pb-6 border-b border-slate-200">
    <div>
      <h1 className="text-3xl font-display font-semibold text-slate-900 tracking-tight">{title}</h1>
      {subtitle && <p className="text-slate-600 mt-1">{subtitle}</p>}
    </div>
    {action}
  </div>
);
const StatCard = ({ label, value, sublabel, accent = 'burgundy' }) => {
  const accents = { burgundy: 'text-burgundy-600', gold: 'text-gold-600', navy: 'text-navy-800', slate: 'text-slate-700' };
  return (
    <div className="card p-5">
      <div className="label">{label}</div>
      <div className={`text-3xl font-display font-semibold ${accents[accent]}`}>{value}</div>
      {sublabel && <div className="text-xs text-slate-500 mt-1">{sublabel}</div>}
    </div>
  );
};
const EmptyState = ({ icon: Icon, title, message, action }) => (
  <div className="flex flex-col items-center justify-center py-16 px-6 text-center">
    {Icon && <Icon className="w-12 h-12 text-slate-300 mb-4" />}
    <h3 className="text-lg font-semibold text-slate-700 mb-1">{title}</h3>
    {message && <p className="text-sm text-slate-500 max-w-sm">{message}</p>}
    {action && <div className="mt-6">{action}</div>}
  </div>
);

// ============================================================================
// SIGN-IN + LAYOUT
// ============================================================================
function SignIn() {
  const { signInAs } = useAuth();
  const [members, setMembers] = useState([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    api.listMembers({ status: 'active', limit: 50 }).then((d) => { setMembers(d.members || []); setLoading(false); }).catch(() => setLoading(false));
  }, []);
  return (
    <div className="min-h-screen flex items-center justify-center bg-cream-100 p-6">
      <div className="card-luxe w-full max-w-md p-10">
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-14 h-14 rounded-full bg-burgundy-600 text-white font-display text-2xl mb-4">FS</div>
          <h1 className="text-3xl font-display font-semibold text-slate-900">Freedom Supercars</h1>
          <p className="text-slate-600 text-sm mt-1">Member Portal</p>
        </div>
        <div className="label">Sign in as</div>
        {loading ? <div className="text-slate-500 text-sm py-4">Loading members...</div>
          : members.length === 0 ? <div className="text-slate-500 text-sm py-4">No members yet. Run the seed script first.</div>
          : <select className="input mb-4" defaultValue="" onChange={(e) => e.target.value && signInAs(e.target.value)}>
              <option value="" disabled>— Select a member —</option>
              {members.map((m) => <option key={m.id} value={m.id}>{m.first_name} {m.last_name} ({m.member_number})</option>)}
            </select>
        }
        <p className="text-xs text-slate-500 text-center mt-6">Mock auth for demo. Production wires this to Firebase Auth.</p>
      </div>
    </div>
  );
}

const NAV = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/fleet', label: 'Fleet', icon: Car },
  { to: '/reservations', label: 'My Reservations', icon: CalendarCheck },
  { to: '/concierge', label: 'MARC (Concierge)', icon: Sparkles },
  { to: '/profile', label: 'Profile', icon: UserCircle },
];

function Layout() {
  const { member, loading, signOut } = useAuth();
  const navigate = useNavigate();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  if (loading) return <div className="min-h-screen flex items-center justify-center text-slate-500">Loading...</div>;
  if (!member) return <SignIn />;
  return (
    <div className="min-h-screen flex">
      <button className="md:hidden fixed top-4 left-4 z-30 p-2 bg-white rounded-lg shadow-card" onClick={() => setSidebarOpen(!sidebarOpen)}>
        {sidebarOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
      </button>
      <aside className={`fixed md:static inset-y-0 left-0 w-64 bg-white border-r border-slate-200 z-20 transform transition-transform md:translate-x-0 ${sidebarOpen ? 'translate-x-0' : '-translate-x-full'} flex flex-col`}>
        <div className="p-6 border-b border-slate-200">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-full bg-burgundy-600 text-white flex items-center justify-center font-display text-sm">FS</div>
            <div>
              <div className="font-display font-semibold text-slate-900">Freedom</div>
              <div className="text-xs text-gold-600 -mt-0.5 tracking-wide">SUPERCARS</div>
            </div>
          </div>
        </div>
        <nav className="flex-1 p-3 space-y-1">
          {NAV.map((item) => (
            <NavLink key={item.to} to={item.to} end={item.to === '/'} onClick={() => setSidebarOpen(false)}
              className={({ isActive }) => `flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors ${isActive ? 'bg-burgundy-50 text-burgundy-700' : 'text-slate-700 hover:bg-slate-50'}`}>
              <item.icon className="w-4 h-4" />
              {item.label}
            </NavLink>
          ))}
        </nav>
        <div className="p-3 border-t border-slate-200">
          <div className="px-3 py-2 mb-2">
            <div className="text-sm font-medium text-slate-900">{member.first_name} {member.last_name}</div>
            <div className="text-xs text-slate-500">{member.member_number}</div>
          </div>
          <button onClick={() => { signOut(); navigate('/'); }} className="w-full flex items-center gap-2 px-3 py-2 rounded-lg text-sm text-slate-700 hover:bg-slate-50">
            <LogOut className="w-4 h-4" /> Sign out
          </button>
        </div>
      </aside>
      <main className="flex-1 min-w-0 p-6 md:p-10 max-w-7xl mx-auto w-full"><Outlet /></main>
      <button onClick={() => navigate('/concierge')} className="fixed bottom-6 right-6 w-14 h-14 rounded-full bg-burgundy-600 hover:bg-burgundy-700 text-white shadow-lux flex items-center justify-center transition-transform hover:scale-105 z-10" title="Ask MARC">
        <MessageSquare className="w-6 h-6" />
      </button>
    </div>
  );
}

// ============================================================================
// PAGES
// ============================================================================
function Dashboard() {
  const { member, subscription } = useAuth();
  const [reservations, setReservations] = useState([]);
  const [featured, setFeatured] = useState([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    Promise.all([api.getMemberReservations(member.id), api.listFleet({})])
      .then(([r, f]) => { setReservations((r.reservations || []).slice(0, 5)); setFeatured((f.vehicles || []).slice(0, 4)); })
      .finally(() => setLoading(false));
  }, [member.id]);
  const upcoming = reservations.filter((r) => ['requested', 'confirmed', 'picked_up'].includes(r.status));
  return (
    <>
      <PageHeader title={`Welcome, ${member.first_name}`} subtitle="Your garage, your schedule. What will you drive today?" />
      {!subscription ? (
        <div className="card p-8 mb-8">
          <EmptyState icon={Gauge} title="No active membership" message="Choose a plan to begin your Freedom Supercars experience." action={<Link to="/profile" className="btn-primary">View plans</Link>} />
        </div>
      ) : (
        <>
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
            <StatCard label="Points remaining" value={subscription.points_remaining?.toLocaleString() ?? '—'} sublabel={`of ${subscription.points_issued} issued · ${subscription.pct_remaining ?? 0}%`} accent="burgundy" />
            <StatCard label="Current plan" value={subscription.driving_days + '-Day'} sublabel={`${subscription.driving_days} driving days/yr`} accent="gold" />
            <StatCard label="Upcoming drives" value={upcoming.length} sublabel={upcoming.length ? 'next ' + formatDistanceToNow(parseISO(upcoming[0].pickup_at)) : 'none scheduled'} accent="navy" />
            <StatCard label="Term ends" value={format(parseISO(subscription.end_date), 'MMM d')} sublabel={format(parseISO(subscription.end_date), 'yyyy')} accent="slate" />
          </div>
          <div className="card p-5 mb-8">
            <div className="flex items-center justify-between mb-2">
              <div className="text-sm font-medium text-slate-700 flex items-center gap-2"><TrendingDown className="w-4 h-4 text-burgundy-600" /> Points usage</div>
              <div className="text-xs text-slate-500">{subscription.points_issued - subscription.points_remaining} used / {subscription.points_issued} issued</div>
            </div>
            <div className="h-3 bg-slate-100 rounded-full overflow-hidden">
              <div className="h-full bg-gradient-to-r from-burgundy-500 to-gold-500 rounded-full transition-all" style={{ width: `${Math.max(4, 100 - (subscription.pct_remaining ?? 100))}%` }} />
            </div>
          </div>
        </>
      )}
      <div className="mb-10">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-xl font-display font-semibold text-slate-900">Upcoming reservations</h2>
          <Link to="/reservations" className="text-sm text-burgundy-600 hover:underline">View all →</Link>
        </div>
        {loading ? <div className="card p-8 flex justify-center"><Spinner /></div>
          : upcoming.length === 0 ? <div className="card p-8"><EmptyState icon={CalendarCheck} title="No upcoming reservations" message="Book a car from the fleet." action={<Link to="/fleet" className="btn-primary">Browse fleet</Link>} /></div>
          : <div className="grid gap-3">{upcoming.map((r) => (
              <div key={r.id} className="card p-4 flex items-center gap-4">
                <div className="w-12 h-12 rounded-lg bg-cream-200 flex items-center justify-center"><Car className="w-5 h-5 text-burgundy-600" /></div>
                <div className="flex-1 min-w-0">
                  <div className="font-medium text-slate-900 truncate">{r.vehicle}</div>
                  <div className="text-sm text-slate-500 flex items-center gap-3 mt-0.5">
                    <span className="flex items-center gap-1"><Clock className="w-3 h-3" />{format(parseISO(r.pickup_at), 'MMM d, h:mma')}</span>
                    <span>·</span><span>{r.days_booked} day{r.days_booked > 1 ? 's' : ''}</span>
                    <span>·</span><span>{r.total_points_cost} pts</span>
                  </div>
                </div>
                <StatusPill status={r.status} />
              </div>
            ))}</div>
        }
      </div>
      <div>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-xl font-display font-semibold text-slate-900">Featured in the garage</h2>
          <Link to="/fleet" className="text-sm text-burgundy-600 hover:underline">Browse all →</Link>
        </div>
        {loading ? <div className="card p-8 flex justify-center"><Spinner /></div>
          : <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
              {featured.map((v) => (
                <Link key={v.vehicle_id} to={`/fleet/${v.vehicle_id}`} className="card p-4 hover:shadow-lux transition-shadow group">
                  <div className="h-28 bg-gradient-to-br from-cream-200 to-slate-100 rounded-lg mb-3 flex items-center justify-center"><Car className="w-8 h-8 text-slate-400 group-hover:text-burgundy-600 transition-colors" /></div>
                  <div className="flex items-start justify-between gap-2 mb-1">
                    <div className="text-xs uppercase tracking-wider text-slate-500">{v.manufacturer}</div>
                    <TierBadge tier={v.tier_id} />
                  </div>
                  <div className="font-medium text-slate-900 truncate">{v.model}</div>
                  <div className="text-xs text-slate-500 mt-1">{v.horsepower} hp · {v.zero_to_60_sec}s 0–60</div>
                </Link>
              ))}
            </div>
        }
      </div>
    </>
  );
}

function Fleet() {
  const [vehicles, setVehicles] = useState([]);
  const [tiers, setTiers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filters, setFilters] = useState({ tier: '', manufacturer: '', status: '' });
  useEffect(() => { api.listTiers().then((d) => setTiers(d.tiers || [])); }, []);
  useEffect(() => {
    setLoading(true);
    api.listFleet(filters).then((d) => setVehicles(d.vehicles || [])).finally(() => setLoading(false));
  }, [filters]);
  const manufacturers = [...new Set(vehicles.map((v) => v.manufacturer))].sort();
  const hasFilters = Object.values(filters).some(Boolean);
  return (
    <>
      <PageHeader title="The Fleet" subtitle={`${vehicles.length} vehicles ready for your next drive`} />
      <div className="card p-4 mb-6 flex flex-wrap items-center gap-3">
        <Filter className="w-4 h-4 text-slate-500" />
        <select className="input max-w-[160px]" value={filters.tier} onChange={(e) => setFilters({ ...filters, tier: e.target.value })}>
          <option value="">All tiers</option>
          {tiers.map((t) => <option key={t.id} value={t.id}>Tier {t.id} — {t.points_per_day} pts/day</option>)}
        </select>
        <select className="input max-w-[200px]" value={filters.manufacturer} onChange={(e) => setFilters({ ...filters, manufacturer: e.target.value })}>
          <option value="">All manufacturers</option>
          {manufacturers.map((m) => <option key={m} value={m}>{m}</option>)}
        </select>
        <select className="input max-w-[160px]" value={filters.status} onChange={(e) => setFilters({ ...filters, status: e.target.value })}>
          <option value="">Any status</option>
          <option value="available">Available</option>
          <option value="reserved">Reserved</option>
          <option value="in_use">In use</option>
          <option value="detailing">Detailing</option>
        </select>
        {hasFilters && <button className="btn-ghost text-xs" onClick={() => setFilters({ tier: '', manufacturer: '', status: '' })}><X className="w-3 h-3" /> Clear</button>}
      </div>
      {loading ? <div className="card p-16 flex justify-center"><Spinner className="w-8 h-8" /></div>
        : vehicles.length === 0 ? <div className="card p-8"><EmptyState icon={Car} title="No vehicles match your filters" /></div>
        : <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
            {vehicles.map((v) => (
              <Link key={v.vehicle_id} to={`/fleet/${v.vehicle_id}`} className="card-luxe overflow-hidden group hover:shadow-lg transition-shadow">
                <div className="h-44 bg-gradient-to-br from-cream-200 via-slate-100 to-navy-50 flex items-center justify-center"><Car className="w-14 h-14 text-slate-300 group-hover:text-burgundy-600 transition-colors" /></div>
                <div className="p-5">
                  <div className="flex items-start justify-between mb-2">
                    <div>
                      <div className="text-xs uppercase tracking-wider text-slate-500">{v.manufacturer}</div>
                      <h3 className="font-display font-semibold text-lg text-slate-900 mt-0.5">{v.model}{v.trim ? <span className="text-slate-600"> {v.trim}</span> : null}</h3>
                    </div>
                    <TierBadge tier={v.tier_id} />
                  </div>
                  <div className="flex items-center gap-3 text-xs text-slate-600 mb-3"><span>{v.horsepower} hp</span><span>·</span><span>{v.top_speed_mph} mph</span><span>·</span><span>{v.zero_to_60_sec}s 0–60</span></div>
                  <div className="flex items-center justify-between pt-3 border-t border-slate-100">
                    <div className="text-sm"><span className="font-semibold text-burgundy-600">{v.points_per_day}</span><span className="text-slate-500 text-xs ml-1">pts/day</span>{v.min_booking_days > 1 && <span className="text-xs text-gold-600 ml-2">· {v.min_booking_days}-day min</span>}</div>
                    <StatusPill status={v.status} />
                  </div>
                </div>
              </Link>
            ))}
          </div>
      }
    </>
  );
}

function AvailabilityCalendar({ vehicleId, minBookingDays, onRange }) {
  const [monthOffset, setMonthOffset] = useState(0);
  const [blocked, setBlocked] = useState([]);
  const [loading, setLoading] = useState(true);
  const [pickup, setPickup] = useState(null);
  const [returnDay, setReturnDay] = useState(null);
  const today = startOfDay(new Date());
  const viewMonth = startOfMonth(addMonths(today, monthOffset));
  const days = eachDayOfInterval({ start: startOfWeek(viewMonth), end: endOfWeek(endOfMonth(viewMonth)) });
  useEffect(() => {
    setLoading(true);
    api.getAvailability(vehicleId, new Date().toISOString(), addMonths(today, 3).toISOString())
      .then((d) => setBlocked(d.blocked_periods || [])).finally(() => setLoading(false));
  }, [vehicleId]);
  const blockedDates = useMemo(() => {
    const set = new Set();
    for (const b of blocked) {
      const s = startOfDay(parseISO(b.pickup_at)), e = startOfDay(parseISO(b.return_at));
      for (let d = s; isBefore(d, e) || isSameDay(d, e); d = addDays(d, 1)) set.add(format(d, 'yyyy-MM-dd'));
    }
    return set;
  }, [blocked]);
  const isBlocked = (d) => blockedDates.has(format(d, 'yyyy-MM-dd'));
  const handleClick = (d) => {
    if (isBefore(d, today) || isBlocked(d)) return;
    if (!pickup || (pickup && returnDay)) { setPickup(d); setReturnDay(null); onRange?.(null); }
    else if (isBefore(d, pickup)) { setPickup(d); }
    else {
      const rangeDays = eachDayOfInterval({ start: pickup, end: d });
      if (rangeDays.some(isBlocked)) { setPickup(d); setReturnDay(null); onRange?.(null); return; }
      setReturnDay(d);
      onRange?.({ pickup_at: pickup.toISOString(), return_at: addDays(d, 1).toISOString(), days: rangeDays.length });
    }
  };
  const inRange = (d) => pickup && returnDay && !isBefore(d, pickup) && !isBefore(returnDay, d);
  return (
    <div>
      <div className="flex items-center justify-between mb-3">
        <button className="btn-ghost p-1" onClick={() => setMonthOffset(Math.max(0, monthOffset - 1))} disabled={monthOffset === 0}><ChevronLeft className="w-4 h-4" /></button>
        <h4 className="font-display text-lg font-semibold">{format(viewMonth, 'MMMM yyyy')}</h4>
        <button className="btn-ghost p-1" onClick={() => setMonthOffset(monthOffset + 1)}><ChevronRight className="w-4 h-4" /></button>
      </div>
      {loading ? <div className="py-8 flex justify-center"><Spinner /></div>
        : <div className="grid grid-cols-7 gap-1 text-center">
            {['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((d, i) => <div key={i} className="text-xs text-slate-500 py-1 font-medium">{d}</div>)}
            {days.map((d) => {
              const dim = !isSameMonth(d, viewMonth), past = isBefore(d, today), blk = isBlocked(d);
              const isPickup = pickup && isSameDay(d, pickup), isReturn = returnDay && isSameDay(d, returnDay);
              const middle = inRange(d) && !isPickup && !isReturn;
              return (
                <button key={d.toISOString()} onClick={() => handleClick(d)} disabled={past || blk}
                  className={`aspect-square rounded-lg text-sm font-medium transition-all ${dim ? 'text-slate-300' : 'text-slate-700'} ${past || blk ? 'line-through text-slate-300 bg-slate-50 cursor-not-allowed' : 'hover:bg-burgundy-50'} ${isPickup || isReturn ? 'bg-burgundy-600 text-white hover:bg-burgundy-700' : ''} ${middle ? 'bg-burgundy-100 text-burgundy-700' : ''}`}>
                  {format(d, 'd')}
                </button>
              );
            })}
          </div>
      }
      <div className="flex gap-4 text-xs text-slate-500 mt-4 pt-3 border-t border-slate-100">
        <div className="flex items-center gap-1.5"><span className="w-3 h-3 rounded bg-burgundy-600" /> Selected</div>
        <div className="flex items-center gap-1.5"><span className="w-3 h-3 rounded bg-slate-100 border border-slate-200" /> Unavailable</div>
        {minBookingDays > 1 && <div className="ml-auto text-gold-600 font-medium">{minBookingDays}-day minimum</div>}
      </div>
    </div>
  );
}

function VehicleDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { subscription, refreshSubscription } = useAuth();
  const [vehicle, setVehicle] = useState(null);
  const [loading, setLoading] = useState(true);
  const [range, setRange] = useState(null);
  const [quote, setQuote] = useState(null);
  const [quoteError, setQuoteError] = useState(null);
  const [booking, setBooking] = useState(false);
  useEffect(() => { api.getVehicle(id).then((d) => setVehicle(d.vehicle)).finally(() => setLoading(false)); }, [id]);
  useEffect(() => {
    if (!range || !subscription) { setQuote(null); setQuoteError(null); return; }
    api.quoteReservation({ subscription_id: subscription.subscription_id, vehicle_id: id, pickup_at: range.pickup_at, return_at: range.return_at })
      .then((d) => { setQuote(d.quote); setQuoteError(null); })
      .catch((err) => { setQuoteError(err.message); setQuote(null); });
  }, [range, subscription, id]);
  const handleBook = async () => {
    if (!range || !subscription) return;
    setBooking(true);
    try {
      let res;
      if (quote?.reservation_token) {
        res = await api.confirmQuoteReservation({ reservation_token: quote.reservation_token });
      } else {
        res = await api.createReservation({
          subscription_id: subscription.subscription_id,
          vehicle_id: id,
          pickup_at: range.pickup_at,
          return_at: range.return_at,
          auto_confirm: true,
        });
      }
      await refreshSubscription();
      navigate(`/reservations?new=${res.reservation.id}`);
    } catch (err) { alert(`Booking failed: ${err.message}`); } finally { setBooking(false); }
  };
  if (loading) return <div className="flex justify-center p-16"><Spinner className="w-8 h-8" /></div>;
  if (!vehicle) return <div>Vehicle not found</div>;
  return (
    <>
      <Link to="/fleet" className="inline-flex items-center gap-1 text-sm text-slate-600 hover:text-burgundy-600 mb-6"><ArrowLeft className="w-4 h-4" /> Back to fleet</Link>
      <div className="card-luxe overflow-hidden mb-6">
        <div className="h-64 bg-gradient-to-br from-cream-200 via-slate-100 to-navy-50 flex items-center justify-center"><Car className="w-24 h-24 text-slate-300" /></div>
        <div className="p-8">
          <div className="flex items-start justify-between flex-wrap gap-4">
            <div>
              <div className="text-sm uppercase tracking-wider text-slate-500">{vehicle.manufacturer} · {vehicle.model_year}</div>
              <h1 className="text-4xl font-display font-semibold text-slate-900 mt-1">{vehicle.model}</h1>
              {vehicle.trim && <div className="text-lg text-slate-600 font-display">{vehicle.trim}</div>}
              {vehicle.exterior_color && <div className="text-sm text-slate-500 mt-2">Exterior: <span className="text-slate-700 font-medium">{vehicle.exterior_color}</span></div>}
            </div>
            <div className="flex flex-col items-end gap-2">
              <TierBadge tier={vehicle.tier_id} className="text-sm px-3 py-1" />
              <StatusPill status={vehicle.status} />
            </div>
          </div>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mt-8">
            <StatCard label="Horsepower" value={vehicle.horsepower || '—'} sublabel="hp" accent="burgundy" />
            <StatCard label="Top Speed" value={vehicle.top_speed_mph || '—'} sublabel="mph" accent="gold" />
            <StatCard label="0–60" value={vehicle.zero_to_60_sec ? `${vehicle.zero_to_60_sec}s` : '—'} accent="navy" />
            <StatCard label="Cost" value={vehicle.points_per_day} sublabel="points/day" accent="slate" />
          </div>
        </div>
      </div>
      <div className="grid md:grid-cols-2 gap-6">
        <div className="card p-6">
          <h3 className="font-display text-xl font-semibold mb-4">Check availability</h3>
          <AvailabilityCalendar vehicleId={id} minBookingDays={vehicle.min_booking_days} onRange={setRange} />
        </div>
        <div className="card p-6">
          <h3 className="font-display text-xl font-semibold mb-4">Booking summary</h3>
          {!range ? <div className="text-slate-500 text-sm py-8 text-center">Select a pickup and return date on the calendar to see pricing.</div>
            : quoteError ? <div className="flex items-start gap-2 p-4 bg-rose-50 border border-rose-100 rounded-lg text-sm text-rose-700"><AlertCircle className="w-4 h-4 mt-0.5" /><div>{quoteError}</div></div>
            : quote ? <div className="space-y-3">
                <div className="flex justify-between text-sm"><span className="text-slate-600">Duration</span><span className="font-medium">{quote.days_booked} day{quote.days_booked > 1 ? 's' : ''}</span></div>
                <div className="flex justify-between text-sm"><span className="text-slate-600">Rate</span><span className="font-medium">{quote.points_per_day} pts/day</span></div>
                <div className="flex justify-between text-sm pt-3 border-t border-slate-100"><span className="text-slate-600">Total cost</span><span className="font-semibold text-burgundy-600">{quote.total_points_cost} points</span></div>
                <div className="flex justify-between text-xs text-slate-500"><span>Balance after</span><span>{quote.balance_after_confirm} / {subscription.points_issued} pts</span></div>
                <button className="btn-primary w-full mt-4" onClick={handleBook} disabled={booking}>{booking ? <Spinner className="w-4 h-4" /> : <><Check className="w-4 h-4" /> Confirm booking</>}</button>
              </div>
            : <div className="flex justify-center py-8"><Spinner /></div>
          }
        </div>
      </div>
    </>
  );
}

function MyReservations() {
  const { member, refreshSubscription } = useAuth();
  const [searchParams] = useSearchParams();
  const highlightId = searchParams.get('new');
  const [reservations, setReservations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('upcoming');
  const load = () => { setLoading(true); api.getMemberReservations(member.id).then((d) => setReservations(d.reservations || [])).finally(() => setLoading(false)); };
  useEffect(load, [member.id]);
  const now = new Date();
  const filtered = reservations.filter((r) => {
    const pickup = parseISO(r.pickup_at);
    if (filter === 'upcoming') return ['requested', 'confirmed'].includes(r.status) && pickup >= now;
    if (filter === 'active') return r.status === 'picked_up';
    if (filter === 'past') return ['returned', 'cancelled', 'no_show'].includes(r.status);
    return true;
  });
  const handleCancel = async (id) => {
    if (!confirm('Cancel this reservation? Points will be refunded if already confirmed.')) return;
    await api.cancelReservation(id, 'Cancelled by member');
    await refreshSubscription(); load();
  };
  return (
    <>
      <PageHeader title="My Reservations" subtitle={`${reservations.length} total`} action={<Link to="/fleet" className="btn-primary">New reservation</Link>} />
      <div className="flex gap-2 mb-6">
        {['upcoming', 'active', 'past', 'all'].map((f) => (
          <button key={f} onClick={() => setFilter(f)} className={`px-4 py-2 rounded-lg text-sm font-medium capitalize transition-colors ${filter === f ? 'bg-burgundy-600 text-white' : 'bg-white text-slate-700 border border-slate-200 hover:bg-slate-50'}`}>{f}</button>
        ))}
      </div>
      {loading ? <div className="card p-16 flex justify-center"><Spinner className="w-8 h-8" /></div>
        : filtered.length === 0 ? <div className="card p-8"><EmptyState icon={CalendarCheck} title={`No ${filter} reservations`} action={filter === 'upcoming' && <Link to="/fleet" className="btn-primary">Browse fleet</Link>} /></div>
        : <div className="space-y-3">{filtered.map((r) => (
            <div key={r.id} className={`card p-5 transition-all ${r.id === highlightId ? 'ring-2 ring-gold-400 shadow-lux' : ''}`}>
              <div className="flex items-start gap-4">
                <div className="w-14 h-14 rounded-lg bg-cream-200 flex items-center justify-center"><Car className="w-6 h-6 text-burgundy-600" /></div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-start justify-between gap-3 mb-1">
                    <div>
                      <div className="font-display font-semibold text-lg text-slate-900">{r.vehicle}</div>
                      <div className="text-xs text-slate-500 font-mono mt-0.5">{r.confirmation_code}</div>
                    </div>
                    <StatusPill status={r.status} />
                  </div>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mt-4 text-sm">
                    <div><div className="text-xs text-slate-500">Pickup</div><div className="font-medium">{format(parseISO(r.pickup_at), 'MMM d')}</div><div className="text-xs text-slate-500">{format(parseISO(r.pickup_at), 'h:mm a')}</div></div>
                    <div><div className="text-xs text-slate-500">Return</div><div className="font-medium">{format(parseISO(r.return_at), 'MMM d')}</div><div className="text-xs text-slate-500">{format(parseISO(r.return_at), 'h:mm a')}</div></div>
                    <div><div className="text-xs text-slate-500">Duration</div><div className="font-medium">{r.days_booked} day{r.days_booked > 1 ? 's' : ''}</div></div>
                    <div><div className="text-xs text-slate-500">Cost</div><div className="font-medium text-burgundy-600">{r.total_points_cost} pts</div></div>
                  </div>
                  {['requested', 'confirmed'].includes(r.status) && (
                    <div className="mt-4 pt-4 border-t border-slate-100 flex gap-2">
                      <button onClick={() => handleCancel(r.id)} className="btn-ghost text-rose-600 hover:bg-rose-50"><X className="w-4 h-4" /> Cancel</button>
                    </div>
                  )}
                </div>
              </div>
            </div>
          ))}</div>
      }
    </>
  );
}

const TXN_ICONS = {
  grant: { icon: Gift, color: 'text-emerald-600' }, debit: { icon: ArrowDown, color: 'text-rose-600' },
  refund: { icon: ArrowUp, color: 'text-emerald-600' }, rollover: { icon: RotateCcw, color: 'text-navy-700' },
  adjustment: { icon: ArrowUp, color: 'text-slate-600' }, bonus: { icon: Gift, color: 'text-gold-600' },
  expiration: { icon: ArrowDown, color: 'text-slate-500' }, forfeit: { icon: ArrowDown, color: 'text-slate-500' },
};

function Profile() {
  const { member, subscription } = useAuth();
  const [history, setHistory] = useState([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => { api.getMemberPointHistory(member.id).then((d) => setHistory(d.transactions || [])).finally(() => setLoading(false)); }, [member.id]);
  return (
    <>
      <PageHeader 
        title="Profile" 
        subtitle={member.member_number || (member.status?.toLowerCase() === 'pending' ? 'Pending Activation' : '—')} 
      />
      <div className="grid md:grid-cols-3 gap-6 mb-10">
        <div className="card p-6 md:col-span-2">
          <h3 className="font-display text-xl font-semibold mb-4">Personal information</h3>
          <div className="grid grid-cols-2 gap-4 text-sm">
            <div><div className="label">First name</div><div className="font-medium">{member.first_name}</div></div>
            <div><div className="label">Preferred name</div><div className="font-medium">{member.preferred_name || member.first_name}</div></div>
            <div><div className="label">Last name</div><div className="font-medium">{member.last_name}</div></div>
            <div className="col-span-2"><div className="label">Email</div><div className="font-medium flex items-center gap-2"><Mail className="w-4 h-4 text-slate-400" /> {member.email}</div></div>
            {member.phone && <div className="col-span-2"><div className="label">Phone</div><div className="font-medium flex items-center gap-2"><Phone className="w-4 h-4 text-slate-400" /> {member.phone}</div></div>}
            {member.city && <div className="col-span-2"><div className="label">Location</div><div className="font-medium flex items-center gap-2"><MapPin className="w-4 h-4 text-slate-400" /> {[member.city, member.state, member.postal_code].filter(Boolean).join(', ')}</div></div>}
            <div><div className="label">Member since</div><div className="font-medium">{member.joined_on ? format(parseISO(member.joined_on), 'MMM d, yyyy') : (member.member_since ? format(parseISO(member.member_since), 'MMM d, yyyy') : '—')}</div></div>
            <div><div className="label">Status</div><div className="font-medium capitalize">{member.status}</div></div>
          </div>
        </div>
        <div className="card-luxe p-6">
          <h3 className="font-display text-xl font-semibold mb-4">Membership</h3>
          {subscription ? <div className="space-y-3 text-sm">
              <div><div className="label">Plan</div><div className="font-semibold text-burgundy-700 text-lg">{subscription.plan_name}</div></div>
              <div><div className="label">Driving days / yr</div><div className="font-medium">{subscription.driving_days}</div></div>
              <div><div className="label">Points remaining</div><div className="font-semibold text-2xl text-gold-600">{subscription.points_remaining?.toLocaleString()}</div><div className="text-xs text-slate-500">of {subscription.points_issued} ({subscription.pct_remaining}%)</div></div>
              <div className="pt-3 border-t border-slate-100"><div className="label">Term</div><div className="text-xs text-slate-600">{format(parseISO(subscription.start_date), 'MMM d, yyyy')} → {format(parseISO(subscription.end_date), 'MMM d, yyyy')}</div></div>
            </div>
            : <div className="text-sm text-slate-500">No active subscription.</div>
          }
        </div>
      </div>
      <h2 className="text-xl font-display font-semibold mb-4">Point history</h2>
      {loading ? <div className="card p-8 flex justify-center"><Spinner /></div>
        : history.length === 0 ? <div className="card p-8 text-center text-slate-500 text-sm">No transactions yet.</div>
        : <div className="card overflow-hidden">
            <table className="w-full text-sm">
              <thead className="bg-slate-50 text-left">
                <tr>
                  <th className="px-4 py-3 text-xs font-semibold uppercase tracking-wider text-slate-600">Type</th>
                  <th className="px-4 py-3 text-xs font-semibold uppercase tracking-wider text-slate-600">Reason</th>
                  <th className="px-4 py-3 text-xs font-semibold uppercase tracking-wider text-slate-600 text-right">Points</th>
                  <th className="px-4 py-3 text-xs font-semibold uppercase tracking-wider text-slate-600 text-right">Balance</th>
                  <th className="px-4 py-3 text-xs font-semibold uppercase tracking-wider text-slate-600 text-right">When</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {history.map((t) => {
                  const meta = TXN_ICONS[t.txn_type] || TXN_ICONS.adjustment;
                  return (
                    <tr key={t.id} className="hover:bg-slate-50">
                      <td className="px-4 py-3"><div className="flex items-center gap-2"><meta.icon className={`w-4 h-4 ${meta.color}`} /><span className="capitalize font-medium">{t.txn_type}</span></div></td>
                      <td className="px-4 py-3 text-slate-600 max-w-md truncate">{t.reason}</td>
                      <td className={`px-4 py-3 text-right font-semibold ${t.points > 0 ? 'text-emerald-600' : 'text-rose-600'}`}>{t.points > 0 ? '+' : ''}{t.points}</td>
                      <td className="px-4 py-3 text-right font-medium">{t.balance_after}</td>
                      <td className="px-4 py-3 text-right text-xs text-slate-500">{format(parseISO(t.created_at), 'MMM d, h:mma')}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
      }
    </>
  );
}

const SUGGESTIONS = [
  'What Ferraris are available this weekend?',
  'How many points do I have left?',
  'Book me the Lamborghini Urus for next Friday for 2 days',
  "What's the difference between a Tier 3 and a Tier 4 car?",
];

function Concierge() {
  const { member, refreshSubscription } = useAuth();
  const displayName = member ? (member.preferred_name || member.first_name) : '';
  const [messages, setMessages] = useState([{ role: 'assistant', content: `Good day${displayName ? ', ' + displayName : ''}. I'm MARC, your Freedom Supercars concierge. I can help you browse the fleet, check availability, quote a reservation, or answer questions about your membership. What can I do for you today?` }]);
  const [input, setInput] = useState('');
  const [sending, setSending] = useState(false);
  const [activeQuote, setActiveQuote] = useState(null);
  const [confirmingQuote, setConfirmingQuote] = useState(false);
  const endRef = useRef(null);
  useEffect(() => { endRef.current?.scrollIntoView({ behavior: 'smooth' }); }, [messages, sending, activeQuote]);
  const send = async (text) => {
    if (!text.trim() || sending) return;
    const userMsg = { role: 'user', content: text };
    const nextHistory = [...messages, userMsg];
    setMessages(nextHistory); setInput(''); setSending(true);
    try {
      const historyForApi = nextHistory.slice(1).filter((m) => m.role === 'user' || m.role === 'assistant').map((m) => ({ role: m.role, content: m.content }));
      const response = await api.conciergeChat({ messages: historyForApi });
      const toolsUsed = response.tools_used || [];
      const newMessages = [...nextHistory];
      if (toolsUsed.length > 0) newMessages.push({ role: 'tool_trace', tools: toolsUsed });
      newMessages.push({ role: 'assistant', content: response.reply });
      setMessages(newMessages);
      if (response.active_quote) {
        setActiveQuote(response.active_quote);
      }
    } catch (err) {
      setMessages([...nextHistory, { role: 'assistant', content: `I apologize, I ran into an issue: ${err.message}` }]);
    } finally { setSending(false); }
  };
  const handleConfirmQuote = async () => {
    if (!activeQuote?.reservation_token) return;
    setConfirmingQuote(true);
    try {
      const res = await api.confirmQuoteReservation({
        reservation_token: activeQuote.reservation_token,
      });
      await refreshSubscription();
      setActiveQuote(null);
      setMessages((prev) => [
        ...prev,
        {
          role: 'assistant',
          content: `Reservation confirmed. Confirmation code is ${res.reservation.confirmation_code}. You can review your drive under My Reservations.`,
        },
      ]);
    } catch (err) {
      alert(`Reservation confirmation failed: ${err.message}`);
    } finally {
      setConfirmingQuote(false);
    }
  };
  return (
    <>
      <PageHeader title="MARC" subtitle="Member Assistance & Reservation Concierge" />
      <div className="card-luxe overflow-hidden flex flex-col" style={{ height: 'calc(100vh - 250px)', minHeight: 500 }}>
        <div className="flex-1 overflow-y-auto p-6 space-y-4">
          {messages.map((m, i) => {
            if (m.role === 'tool_trace') return (
              <div key={i} className="flex justify-center">
                <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-gold-50 border border-gold-100 text-xs text-gold-700"><Wrench className="w-3 h-3" />{m.tools.map((t) => t.name.replace(/_/g, ' ')).join(' · ')}</div>
              </div>
            );
            const isUser = m.role === 'user';
            return (
              <div key={i} className={`flex gap-3 ${isUser ? 'flex-row-reverse' : ''}`}>
                <div className={`flex-shrink-0 w-9 h-9 rounded-full flex items-center justify-center ${isUser ? 'bg-slate-200' : 'bg-burgundy-600'}`}>
                  {isUser ? <User className="w-4 h-4 text-slate-700" /> : <Sparkles className="w-4 h-4 text-white" />}
                </div>
                <div className={`max-w-[80%] rounded-2xl px-4 py-3 text-sm leading-relaxed ${isUser ? 'bg-burgundy-600 text-white rounded-tr-sm' : 'bg-cream-100 text-slate-900 rounded-tl-sm'}`}>
                  {m.content.split('\n').map((line, idx) => <p key={idx} className={idx > 0 ? 'mt-2' : ''}>{line}</p>)}
                </div>
              </div>
            );
          })}
          {sending && (
            <div className="flex gap-3">
              <div className="w-9 h-9 rounded-full bg-burgundy-600 flex items-center justify-center"><Sparkles className="w-4 h-4 text-white" /></div>
              <div className="bg-cream-100 rounded-2xl rounded-tl-sm px-4 py-3 flex items-center gap-2 text-sm text-slate-500"><Loader2 className="w-4 h-4 animate-spin" /> MARC is thinking...</div>
            </div>
          )}
          <div ref={endRef} />
        </div>
        {activeQuote && (
          <div className="mx-6 mb-3 p-4 rounded-xl bg-gold-50 border border-gold-200 shadow-sm flex flex-col md:flex-row md:items-center justify-between gap-3">
            <div>
              <div className="text-xs uppercase font-semibold text-gold-700 tracking-wider flex items-center gap-1.5">
                <Sparkles className="w-3.5 h-3.5 text-gold-600" /> Ephemeral Reservation Quote
              </div>
              <div className="text-sm font-semibold text-slate-900 mt-0.5">
                {activeQuote.vehicle_name} ({activeQuote.days_booked} day{activeQuote.days_booked > 1 ? 's' : ''})
              </div>
              <div className="text-xs text-slate-600 mt-0.5">
                Cost: <span className="font-semibold text-burgundy-700">{activeQuote.total_points_cost} points</span> ({activeQuote.points_per_day} pts/day) · Remaining: {activeQuote.balance_after} pts
              </div>
            </div>
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={handleConfirmQuote}
                disabled={confirmingQuote}
                className="btn-primary py-2 px-4 text-xs font-semibold flex items-center gap-1.5"
              >
                {confirmingQuote ? <Spinner className="w-3.5 h-3.5" /> : <Check className="w-3.5 h-3.5" />}
                Confirm Reservation
              </button>
              <button
                type="button"
                onClick={() => setActiveQuote(null)}
                className="text-xs text-slate-500 hover:text-slate-700 px-2 py-1"
              >
                Dismiss
              </button>
            </div>
          </div>
        )}
        {messages.length === 1 && (
          <div className="px-6 pb-2">
            <div className="flex flex-wrap gap-2">
              {SUGGESTIONS.map((s) => (
                <button key={s} onClick={() => send(s)} className="px-3 py-1.5 text-xs bg-white border border-slate-200 rounded-full text-slate-700 hover:border-burgundy-300 hover:text-burgundy-700 transition-colors">{s}</button>
              ))}
            </div>
          </div>
        )}
        <form onSubmit={(e) => { e.preventDefault(); send(input); }} className="p-4 border-t border-slate-100 flex gap-2 bg-white">
          <input className="input flex-1" placeholder="Ask MARC anything..." value={input} onChange={(e) => setInput(e.target.value)} disabled={sending} />
          <button type="submit" className="btn-primary" disabled={!input.trim() || sending}><Send className="w-4 h-4" /></button>
        </form>
      </div>
    </>
  );
}

// ============================================================================
// APP
// ============================================================================
export default function App() {
  return (
    <AuthProvider>
      <Routes>
        <Route path="/" element={<Layout />}>
          <Route index element={<Dashboard />} />
          <Route path="fleet" element={<Fleet />} />
          <Route path="fleet/:id" element={<VehicleDetail />} />
          <Route path="reservations" element={<MyReservations />} />
          <Route path="profile" element={<Profile />} />
          <Route path="concierge" element={<Concierge />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Route>
      </Routes>
    </AuthProvider>
  );
}
