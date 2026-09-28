import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { signToken, requireAuth } from '../middleware/auth.js';
import { HttpError } from '../middleware/errorHandler.js';

export const authRouter = Router();

const tokenRequestSchema = z.object({
  member_id: z.string().uuid(),
});

// POST /v1/auth/token - exchange member_id for verified JWT
authRouter.post('/token', async (req, res) => {
  const { member_id } = tokenRequestSchema.parse(req.body);

  const memberResult = await query(
    `SELECT id, member_number, first_name, last_name, email, phone, status
       FROM fs.members
      WHERE id = $1`,
    [member_id]
  );

  if (memberResult.rowCount === 0) {
    throw new HttpError(404, 'Member not found');
  }

  const member = memberResult.rows[0];
  if (member.status === 'cancelled' || member.status === 'expired') {
    throw new HttpError(403, `Account is ${member.status}`);
  }

  const token = signToken({
    memberId: member.id,
    memberNumber: member.member_number,
    email: member.email,
  });

  res.json({
    token,
    member,
  });
});

// GET /v1/auth/me - inspect current verified identity
authRouter.get('/me', requireAuth, async (req, res) => {
  const memberResult = await query(
    `SELECT id, member_number, first_name, last_name, email, phone, status
       FROM fs.members
      WHERE id = $1`,
    [req.user.memberId]
  );

  if (memberResult.rowCount === 0) {
    throw new HttpError(404, 'Member not found');
  }

  res.json({
    member: memberResult.rows[0],
    claims: req.user,
  });
});
