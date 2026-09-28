import jwt from 'jsonwebtoken';
import { config } from '../config.js';
import { HttpError } from './errorHandler.js';

export function signToken(payload, options = {}) {
  return jwt.sign(payload, config.jwtSecret, {
    expiresIn: '7d',
    ...options,
  });
}

export function verifyToken(token) {
  return jwt.verify(token, config.jwtSecret);
}

export function requireAuth(req, _res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new HttpError(401, 'Authentication required: missing Bearer token');
  }

  const token = authHeader.slice(7).trim();
  try {
    const decoded = verifyToken(token);
    req.user = decoded;
    return next();
  } catch (err) {
    throw new HttpError(401, 'Authentication failed: invalid or expired token');
  }
}

export function optionalAuth(req, _res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    req.user = null;
    return next();
  }

  const token = authHeader.slice(7).trim();
  try {
    req.user = verifyToken(token);
  } catch (_err) {
    req.user = null;
  }
  return next();
}
