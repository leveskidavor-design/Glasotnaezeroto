import { createFileRoute } from '@tanstack/react-router'
import { z } from 'zod'
import { HomeLogin } from '@/components/home-login'

export const Route = createFileRoute('/')({
  /** Set when a boat's tour sent an unregistered device back to log in. */
  validateSearch: z.object({
    boat: z.string().max(40).optional().catch(undefined),
    reason: z.enum(['no-device', 'revoked']).optional().catch(undefined),
  }),
  component: HomeLogin,
})
