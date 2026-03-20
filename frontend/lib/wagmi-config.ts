import { http, createConfig, createStorage, cookieStorage } from 'wagmi'
import { mainnet, hardhat } from 'wagmi/chains'
import { injected, metaMask } from 'wagmi/connectors'

// Local Anvil chain configuration
const anvil = {
  ...hardhat,
  id: 31337,
  name: 'Anvil',
  rpcUrls: {
    default: {
      http: ['http://127.0.0.1:8545'],
    },
  },
} as const

export const config = createConfig({
  chains: [anvil, mainnet],
  connectors: [
    injected(),
    metaMask(),
  ],
  storage: createStorage({
    storage: cookieStorage,
  }),
  transports: {
    [anvil.id]: http('http://127.0.0.1:8545'),
    [mainnet.id]: http(),
  },
  ssr: true,
})
