'use client'

import { useAccount, useConnect, useDisconnect, useReadContract } from 'wagmi'
import { formatUnits } from 'viem'
import { MOCK_ERC20_ADDRESS, ERC20_ABI } from '@/lib/contracts'
import { Wallet, Coins, LogOut, ChevronDown } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'

export function Header() {
  const { address, isConnected } = useAccount()
  const { connectors, connect, isPending } = useConnect()
  const { disconnect } = useDisconnect()

  const { data: tokenBalance } = useReadContract({
    address: MOCK_ERC20_ADDRESS,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
    },
  })

  const { data: tokenSymbol } = useReadContract({
    address: MOCK_ERC20_ADDRESS,
    abi: ERC20_ABI,
    functionName: 'symbol',
  })

  const formatAddress = (addr: string) => {
    return `${addr.slice(0, 6)}...${addr.slice(-4)}`
  }

  return (
    <header className="sticky top-0 z-50 border-b border-border/50 bg-background/80 backdrop-blur-lg">
      <div className="mx-auto flex h-16 max-w-7xl items-center justify-between px-4 sm:px-6 lg:px-8">
        <div className="flex items-center gap-3">
          <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-gradient-to-br from-primary to-accent shadow-sm">
            <Coins className="h-5 w-5 text-primary-foreground" />
          </div>
          <div className="flex flex-col">
            <span className="text-base font-semibold tracking-tight text-foreground">P2P Lending</span>
            <span className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">Protocol</span>
          </div>
        </div>

        <div className="flex items-center gap-3">
          {isConnected && tokenBalance !== undefined && (
            <div className="hidden items-center gap-2.5 rounded-lg border border-border/50 bg-secondary/50 px-3.5 py-2 sm:flex">
              <div className="flex h-6 w-6 items-center justify-center rounded-md bg-primary/10">
                <Wallet className="h-3.5 w-3.5 text-primary" />
              </div>
              <div className="flex items-baseline gap-1.5">
                <span className="text-sm font-semibold tabular-nums text-foreground">
                  {Number(formatUnits(tokenBalance, 18)).toLocaleString(undefined, {
                    maximumFractionDigits: 2,
                  })}
                </span>
                <span className="text-xs font-medium text-muted-foreground">{tokenSymbol || 'TOKEN'}</span>
              </div>
            </div>
          )}

          {isConnected ? (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="outline" className="gap-2 border-border/50 bg-secondary/50">
                  <div className="flex h-5 w-5 items-center justify-center rounded-full bg-primary/20">
                    <Wallet className="h-3 w-3 text-primary" />
                  </div>
                  <span className="hidden text-sm font-medium sm:inline">
                    {formatAddress(address!)}
                  </span>
                  <ChevronDown className="h-4 w-4 text-muted-foreground" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-48">
                <DropdownMenuItem
                  onClick={() => disconnect()}
                  className="cursor-pointer gap-2 text-destructive focus:text-destructive"
                >
                  <LogOut className="h-4 w-4" />
                  Disconnect
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          ) : (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button className="gap-2" disabled={isPending}>
                  <Wallet className="h-4 w-4" />
                  {isPending ? 'Connecting...' : 'Connect Wallet'}
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-56">
                {connectors.map((connector) => (
                  <DropdownMenuItem
                    key={connector.uid}
                    onClick={() => connect({ connector })}
                    className="cursor-pointer gap-2"
                  >
                    <Wallet className="h-4 w-4 text-primary" />
                    {connector.name}
                  </DropdownMenuItem>
                ))}
              </DropdownMenuContent>
            </DropdownMenu>
          )}
        </div>
      </div>
    </header>
  )
}
