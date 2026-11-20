'use client'

/**
 * Skyline mark.
 *
 * A bond: a heavy outer ring (the curator's capital) sitting behind a lighter
 * inner disc (depositor capital), with the curator's segment visibly smaller
 * and subordinate — the same visual grammar the protocol enforces.
 */
export function Logo({ size = 40 }: { size?: number }) {
  const id = `skyline-logo-${size}`
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 64 64"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      role="img"
      aria-label="Skyline"
    >
      <defs>
        <linearGradient id={`${id}-bg`} x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stopColor="#0c4a6e" />
          <stop offset="55%" stopColor="#0284c7" />
          <stop offset="100%" stopColor="#22d3ee" />
        </linearGradient>
        <linearGradient id={`${id}-bond`} x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stopColor="#f59e0b" />
          <stop offset="100%" stopColor="#fb923c" />
        </linearGradient>
      </defs>

      <rect width="64" height="64" rx="16" fill={`url(#${id}-bg)`} />

      {/* Curator bond: the subordinate, outer segment */}
      <circle cx="32" cy="32" r="19" stroke={`url(#${id}-bond)`} strokeWidth="5" strokeOpacity="0.9" />

      {/* Depositor capital: the dominant, inner disc */}
      <circle cx="32" cy="32" r="10" fill="#ffffff" fillOpacity="0.92" />

      {/* The gate: a hard stop on the bond ring */}
      <path
        d="M32 9 L32 17"
        stroke="#ffffff"
        strokeWidth="5"
        strokeLinecap="round"
        strokeOpacity="0.95"
      />
    </svg>
  )
}
