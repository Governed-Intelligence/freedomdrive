import { Router } from 'express';
import { z } from 'zod';
import rateLimit from 'express-rate-limit';
import { chat } from '../services/marc.js';
import { requireAuth } from '../middleware/auth.js';

export const conciergeRouter = Router();

// Rate limiting: 10 requests per minute per IP / member
const conciergeLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    error: 'rate_limited',
    message: 'Too many concierge requests. Concierge is capped at 10 requests per minute.',
  },
});

const chatSchema = z.object({
  messages: z
    .array(
      z.object({
        role: z.enum(['user', 'assistant']),
        content: z.string().min(1).max(4000),
      })
    )
    .min(1)
    .max(20),
});

// POST /v1/concierge/chat
// Requires verified JWT Bearer token.
// Autonomous booking writes are removed; quotes return ephemeral tokens
// that must be explicitly confirmed out-of-band via the web UI.
conciergeRouter.post('/chat', conciergeLimiter, requireAuth, async (req, res) => {
  const { messages } = chatSchema.parse(req.body);
  const memberId = req.user.memberId;

  const result = await chat({ messages, memberId });
  res.json(result);
});
