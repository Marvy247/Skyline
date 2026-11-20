'use client'

/**
 * Root providers: React Query for contract reads, wagmi for wallet + chain.
 */

import { useState } from "react"
import { QueryClientProvider } from "@tanstack/react-query"
import { WagmiProvider } from "wagmi"

import { getWagmiConfig, makeQueryClient } from "@/lib/web3"

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(() => makeQueryClient())
  const [wagmiConfig] = useState(() => getWagmiConfig())

  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </WagmiProvider>
  )
}
