// MARC - Member Assistance & Reservation Concierge
// Uses Anthropic tool use to browse the fleet, check availability, price bookings,
// and generate ephemeral reservation quote tokens that members confirm via the UI.

import Anthropic from '@anthropic-ai/sdk';
import { config } from '../config.js';
import { query } from '../db.js';
import { signToken } from '../middleware/auth.js';
import {
  loadBookingContext,
  validateBooking,
  checkAnnualTierCap,
} from './reservations.js';

const client = config.anthropicApiKey
  ? new Anthropic({ apiKey: config.anthropicApiKey })
  : null;

const MODEL = 'claude-sonnet-4-5';
const MAX_TOKENS = 2048;
const MAX_TOOL_ITERATIONS = 4; // guardrail against runaway loops

// ----------------------------------------------------------------------------
// Tool schemas - what MARC is allowed to do
// Autonomous mutation writes (create_reservation) have been removed.
// Booking quotes return an ephemeral reservation_token for out-of-band confirmation.
// ----------------------------------------------------------------------------

const TOOLS = [
  {
    name: 'search_fleet',
    description:
      'Search the fleet of available supercars. Filter by tier (1-5), manufacturer name, or status. Returns matching vehicles with model, tier, points/day, HP, and status.',
    input_schema: {
      type: 'object',
      properties: {
        tier: { type: 'integer', minimum: 1, maximum: 5, description: 'Vehicle tier (1=entry, 5=flagship)' },
        manufacturer: { type: 'string', description: 'Manufacturer name (e.g. Ferrari, Porsche, Lamborghini)' },
        status: { type: 'string', enum: ['available', 'reserved', 'in_use', 'maintenance', 'detailing'] },
        max_results: { type: 'integer', minimum: 1, maximum: 20, default: 10 },
      },
    },
  },
  {
    name: 'get_vehicle_details',
    description: 'Get full detail on one vehicle by ID. Includes specs, tier, cost, and booking rules.',
    input_schema: {
      type: 'object',
      properties: { vehicle_id: { type: 'string', description: 'UUID of the vehicle' } },
      required: ['vehicle_id'],
    },
  },
  {
    name: 'check_availability',
    description: 'Check availability for a specific vehicle in a date window. Returns blocked periods where the vehicle is already booked.',
    input_schema: {
      type: 'object',
      properties: {
        vehicle_id: { type: 'string' },
        from_date: { type: 'string', description: 'ISO date, e.g. 2026-04-20' },
        to_date: { type: 'string', description: 'ISO date' },
      },
      required: ['vehicle_id', 'from_date', 'to_date'],
    },
  },
  {
    name: 'get_member_balance',
    description: 'Get the current member point balance and active subscription. Only call if a member_id is available in the conversation context.',
    input_schema: { type: 'object', properties: {} },
  },
  {
    name: 'quote_booking',
    description: 'Price a prospective booking, verify availability and annual tier caps, and generate an ephemeral reservation token. The member must confirm this quote via the web UI to create the reservation.',
    input_schema: {
      type: 'object',
      properties: {
        vehicle_id: { type: 'string', description: 'UUID of the vehicle' },
        pickup_at: { type: 'string', description: 'ISO datetime, e.g. 2026-04-20T10:00:00Z' },
        return_at: { type: 'string', description: 'ISO datetime, e.g. 2026-04-23T18:00:00Z' },
      },
      required: ['vehicle_id', 'pickup_at', 'return_at'],
    },
  },
  {
    name: 'list_upcoming_reservations',
    description: 'List the current member upcoming reservations. Requires member context.',
    input_schema: { type: 'object', properties: {} },
  },
];

// ----------------------------------------------------------------------------
// Tool executors - database interaction with safety wrappers
// ----------------------------------------------------------------------------

async function execSearchFleet({ tier, manufacturer, status, max_results = 10 }) {
  try {
    const clauses = [];
    const values = [];
    if (tier) { values.push(tier); clauses.push(`tier_id = $${values.length}`); }
    if (manufacturer) { values.push(`%${manufacturer}%`); clauses.push(`manufacturer ILIKE $${values.length}`); }
    if (status) { values.push(status); clauses.push(`status = $${values.length}`); }
    const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';
    values.push(max_results);
    const result = await query(
      `SELECT vehicle_id, manufacturer, model, trim, model_year, exterior_color,
              tier_id, points_per_day, min_booking_days, horsepower, top_speed_mph,
              zero_to_60_sec, status
         FROM fs.v_active_fleet ${where}
         ORDER BY tier_id, manufacturer LIMIT $${values.length}`,
      values
    );
    return { count: result.rowCount, vehicles: result.rows };
  } catch (err) {
    return { error: err.message };
  }
}

async function execGetVehicleDetails({ vehicle_id }) {
  try {
    const result = await query(`SELECT * FROM fs.v_active_fleet WHERE vehicle_id = $1`, [vehicle_id]);
    if (result.rowCount === 0) return { error: 'Vehicle not found' };
    return { vehicle: result.rows[0] };
  } catch (err) {
    return { error: err.message };
  }
}

async function execCheckAvailability({ vehicle_id, from_date, to_date }) {
  try {
    const result = await query(
      `SELECT confirmation_code, pickup_at, return_at, status
         FROM fs.reservations
        WHERE vehicle_id = $1
          AND status IN ('requested','confirmed','picked_up')
          AND booking_period && tstzrange($2::timestamptz, $3::timestamptz, '[)')
        ORDER BY pickup_at`,
      [vehicle_id, from_date, to_date]
    );
    return {
      vehicle_id,
      window: { from: from_date, to: to_date },
      blocked_periods: result.rows,
      fully_available: result.rowCount === 0,
    };
  } catch (err) {
    return { error: err.message };
  }
}

async function execGetMemberBalance({ memberId }) {
  if (!memberId) return { error: 'No member context: MARC requires an authenticated member to check balance.' };
  try {
    const result = await query(
      `SELECT * FROM fs.v_member_subscription_status WHERE member_id = $1`,
      [memberId]
    );
    if (result.rowCount === 0) return { error: 'No active subscription found for this member.' };
    return { subscription: result.rows[0] };
  } catch (err) {
    return { error: err.message };
  }
}

async function execQuoteBooking({ vehicle_id, pickup_at, return_at, memberId }) {
  if (!memberId) return { error: 'Member authentication required to quote a booking.' };
  try {
    const sub = await query(
      `SELECT id FROM fs.member_subscriptions WHERE member_id = $1 AND status = 'active' LIMIT 1`,
      [memberId]
    );
    if (sub.rowCount === 0) return { error: 'No active subscription found for this member.' };

    const ctx = await loadBookingContext({ vehicleId: vehicle_id, subscriptionId: sub.rows[0].id });
    const { days, pointsPerDay, totalCost } = await validateBooking(ctx, { pickupAt: pickup_at, returnAt: return_at });
    await checkAnnualTierCap(ctx, days);

    // Verify vehicle availability in date window
    const conflict = await query(
      `SELECT id FROM fs.reservations
        WHERE vehicle_id = $1
          AND status IN ('confirmed','picked_up')
          AND booking_period && tstzrange($2::timestamptz, $3::timestamptz, '[)')
        LIMIT 1`,
      [vehicle_id, pickup_at, return_at]
    );
    if (conflict.rowCount > 0) {
      return { error: 'This vehicle is already booked for those dates. Please choose different dates or another vehicle.' };
    }

    // Get vehicle display details
    const veh = await query(
      `SELECT mf.name || ' ' || vm.model_name AS display_name
         FROM fs.vehicles v
         JOIN fs.vehicle_models vm ON vm.id = v.model_id
         JOIN fs.manufacturers mf ON mf.id = vm.manufacturer_id
        WHERE v.id = $1`,
      [vehicle_id]
    );
    const vehicleName = veh.rows[0]?.display_name || 'Supercar';

    // Issue an ephemeral quote token (valid for 15 minutes)
    const quotePayload = {
      type: 'reservation_quote',
      memberId,
      subscriptionId: sub.rows[0].id,
      vehicleId: vehicle_id,
      pickupAt: pickup_at,
      returnAt: return_at,
      days,
      pointsPerDay,
      totalCost,
    };
    const reservationToken = signToken(quotePayload, { expiresIn: '15m' });

    return {
      quote: {
        reservation_token: reservationToken,
        vehicle_id,
        vehicle_name: vehicleName,
        pickup_at,
        return_at,
        days_booked: days,
        points_per_day: pointsPerDay,
        total_points_cost: totalCost,
        balance_before: ctx.balance,
        balance_after: ctx.balance - totalCost,
        tier_id: ctx.tier_id,
        expires_in_minutes: 15,
        action_required: 'Member must review details and click Confirm in the reservation UI to finalize booking.',
      },
    };
  } catch (err) {
    return { error: err.message };
  }
}

async function execListUpcomingReservations({ memberId }) {
  if (!memberId) return { error: 'Member authentication required.' };
  try {
    const result = await query(
      `SELECT r.confirmation_code, r.status, r.pickup_at, r.return_at,
              r.days_booked, r.total_points_cost,
              mf.name || ' ' || vm.model_name AS vehicle
         FROM fs.reservations r
         JOIN fs.vehicles v ON v.id = r.vehicle_id
         JOIN fs.vehicle_models vm ON vm.id = v.model_id
         JOIN fs.manufacturers mf ON mf.id = vm.manufacturer_id
        WHERE r.member_id = $1
          AND r.status IN ('requested','confirmed','picked_up')
          AND r.pickup_at >= now()
        ORDER BY r.pickup_at
        LIMIT 20`,
      [memberId]
    );
    return { count: result.rowCount, reservations: result.rows };
  } catch (err) {
    return { error: err.message };
  }
}

// Dispatch table
async function runTool(name, input, ctx) {
  switch (name) {
    case 'search_fleet': return execSearchFleet(input);
    case 'get_vehicle_details': return execGetVehicleDetails(input);
    case 'check_availability': return execCheckAvailability(input);
    case 'get_member_balance': return execGetMemberBalance({ ...input, memberId: ctx.memberId });
    case 'quote_booking': return execQuoteBooking({ ...input, memberId: ctx.memberId });
    case 'list_upcoming_reservations': return execListUpcomingReservations({ memberId: ctx.memberId });
    default: return { error: `Unknown tool: ${name}` };
  }
}

// ----------------------------------------------------------------------------
// System prompt
// ----------------------------------------------------------------------------

function buildSystemPrompt({ memberContext, todayIso }) {
  return `You are MARC - the Member Assistance & Reservation Concierge for Freedom Supercars, a members-only supercar club in Houston, Texas (2119 Brittmoore Rd).

Your role: help members browse the fleet, understand plans and points, check availability, and price prospective reservations. Speak with the warmth and precision of a five-star hotel concierge. Never be pushy. Never invent data - always use the tools to look things up.

# What you know about Freedom Supercars
- 4 membership plans: 15, 30, 60, and 100 driving days per year (PLAN_15/30/60/100)
- Vehicles are grouped into 5 tiers (T1-T5); each tier costs a different number of tier points per day
- Tier 5 (flagship - Ferrari 296 GTB, Rolls Royce Cullinan) requires a 3-day minimum booking
- Fleet includes Ferrari, Porsche, Lamborghini, McLaren, Aston Martin, Bentley, Rolls-Royce, and more
- Today is ${todayIso}

# Member context
${memberContext || 'This user is not signed in. You can browse the fleet but cannot check their balance or quote on their behalf.'}

# Safety & Reservation Rules
1. Use tools whenever the user asks about specific vehicles, availability, or their account.
2. For bookings: ALWAYS call quote_booking to calculate points, verify availability, and generate an ephemeral reservation token.
3. You CANNOT directly execute or mutate reservations. Once a quote is produced, tell the member what the booking costs and inform them they can finalize it by tapping the Confirm button in the reservation card on their screen.
4. When you do not have a specific vehicle ID, use search_fleet first to find candidates.
5. Interpret relative dates ("this weekend", "next Friday for 2 days") relative to today date above.
6. Keep replies concise: 2 to 4 short sentences unless the user asks for more detail.
7. If a member asks for something outside your capabilities (e.g. changing billing methods, cancelling membership, filing damage claims), politely direct them to call the club at 832-726-1940.`;
}

// ----------------------------------------------------------------------------
// Main entry point - multi-turn tool-use loop
// ----------------------------------------------------------------------------

export async function chat({ messages, memberId = null }) {
  if (!client) {
    return {
      reply: 'MARC is offline - no Anthropic API key is configured. Please contact support.',
      tools_used: [],
    };
  }

  // Load member context up front if authenticated
  let memberContext = null;
  if (memberId) {
    const m = await query(
      `SELECT first_name, last_name, member_number FROM fs.members WHERE id = $1`,
      [memberId]
    );
    if (m.rowCount > 0) {
      const row = m.rows[0];
      memberContext = `The member is ${row.first_name} ${row.last_name} (${row.member_number}). Their member_id is verified and available to tools.`;
    }
  }

  const system = buildSystemPrompt({
    memberContext,
    todayIso: new Date().toISOString().slice(0, 10),
  });

  const apiMessages = messages.map((m) => ({
    role: m.role,
    content: typeof m.content === 'string' ? m.content : m.content,
  }));

  const toolsUsed = [];
  let activeQuote = null;

  for (let iter = 0; iter < MAX_TOOL_ITERATIONS; iter++) {
    const response = await client.messages.create({
      model: MODEL,
      max_tokens: MAX_TOKENS,
      system,
      tools: TOOLS,
      messages: apiMessages,
    });

    const toolUses = response.content.filter((b) => b.type === 'tool_use');

    if (toolUses.length === 0 || response.stop_reason === 'end_turn') {
      const text = response.content
        .filter((b) => b.type === 'text')
        .map((b) => b.text)
        .join('\n')
        .trim();
      return {
        reply: text || 'I apologize, I lost my train of thought. Could you please rephrase?',
        tools_used: toolsUsed,
        active_quote: activeQuote,
      };
    }

    apiMessages.push({ role: 'assistant', content: response.content });

    const toolResults = [];
    for (const tu of toolUses) {
      const result = await runTool(tu.name, tu.input, { memberId });
      if (tu.name === 'quote_booking' && result?.quote) {
        activeQuote = result.quote;
      }
      toolsUsed.push({ name: tu.name, input: tu.input, result_preview: summarize(result) });
      toolResults.push({
        type: 'tool_result',
        tool_use_id: tu.id,
        content: JSON.stringify(result),
      });
    }
    apiMessages.push({ role: 'user', content: toolResults });
  }

  return {
    reply: 'I am having trouble completing that request. Could you please try rephrasing, or call the club at 832-726-1940 for assistance?',
    tools_used: toolsUsed,
    active_quote: activeQuote,
  };
}

function summarize(result) {
  if (result.error) return `error: ${result.error.slice(0, 80)}`;
  if (result.vehicles) return `${result.count} vehicles`;
  if (result.blocked_periods) return `${result.blocked_periods.length} blocks in window`;
  if (result.subscription) return `balance: ${result.subscription.points_remaining} pts`;
  if (result.quote) return `quoted: ${result.quote.total_points_cost} pts (token issued)`;
  if (result.reservations) return `${result.count} upcoming`;
  return 'ok';
}
