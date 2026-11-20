/**
 * wagmi / viem configuration for the Skyline dashboard.
 *
 * The config is created lazily and cached so that importing this module on the
 * server does not open a provider connection.
 */

import { QueryClient } from "@tanstack/react-query"
import { http, createConfig, createStorage } from "wagmi"
import { baseSepolia, unichainSepolia } from "wagmi/chains"
import { injected } from "wagmi/connectors"
import type { Transport } from "viem"

import { config as mandateConfig } from "@/lib/contracts"

export const supportedChains = [baseSepolia, unichainSepolia] as const

function resolveChain() {
  switch (mandateConfig.chainId) {
    case 1301:
      return unichainSepolia
    case 84532:
    default:
      return baseSepolia
  }
}

let _config: ReturnType<typeof createConfig> | undefined

export function getWagmiConfig() {
  if (_config) return _config

  const chain = resolveChain()

  _config = createConfig({
    chains: [chain],
    connectors: [injected({ shimDisconnect: true })],
    transports: {
      [chain.id]: http(mandateConfig.rpcUrl, {
        batch: { wait: 64 },
        retryCount: 3,
      }),
    } as Record<84532 | 1301, Transport>,
    ssr: true,
    storage: createStorage({
      storage: typeof window !== "undefined" ? window.localStorage : undefined,
    }),
  })

  return _config
}

/** A dedicated QueryClient for contract reads. */
export function makeQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 5_000,
        refetchOnWindowFocus: false,
        retry: 1,
      },
    },
  })
}

/** Chain short name for display. */
export function chainName(): string {
  return resolveChain().name
}
