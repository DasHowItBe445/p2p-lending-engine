'use client'

import { useAccount } from 'wagmi'
import { Header } from '@/components/header'
import { LenderPanel } from '@/components/panels/lender-panel'
import { BorrowerPanel } from '@/components/panels/borrower-panel'
import { ActionsPanel } from '@/components/panels/actions-panel'
import { Dashboard } from '@/components/dashboard/dashboard'
import { Card, CardContent } from '@/components/ui/card'
import { Wallet, Shield, Zap, Users, ArrowRight } from 'lucide-react'

function ConnectionPrompt() {
  return (
    <div className="flex min-h-[70vh] flex-col items-center justify-center px-4">
      <div className="mb-6 flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br from-primary to-accent shadow-lg shadow-primary/20">
        <Wallet className="h-8 w-8 text-primary-foreground" />
      </div>
      <h2 className="mb-2 text-center text-3xl font-bold tracking-tight text-foreground">
        Connect Your Wallet
      </h2>
      <p className="mb-10 max-w-lg text-center text-base text-muted-foreground leading-relaxed">
        Connect your wallet to access the P2P lending protocol. Lend, borrow, and earn competitive interest rates on your crypto assets.
      </p>
      <div className="grid w-full max-w-3xl grid-cols-1 gap-5 sm:grid-cols-3">
        <Card className="group border-border/50 bg-card/50 backdrop-blur transition-all hover:border-primary/30 hover:bg-card">
          <CardContent className="flex flex-col items-center p-6">
            <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-xl bg-primary/10 transition-colors group-hover:bg-primary/20">
              <Shield className="h-6 w-6 text-primary" />
            </div>
            <h3 className="mb-1.5 text-sm font-semibold text-foreground">Secure Protocol</h3>
            <p className="text-center text-xs text-muted-foreground leading-relaxed">
              Non-custodial smart contracts with audited security
            </p>
          </CardContent>
        </Card>
        <Card className="group border-border/50 bg-card/50 backdrop-blur transition-all hover:border-primary/30 hover:bg-card">
          <CardContent className="flex flex-col items-center p-6">
            <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-xl bg-primary/10 transition-colors group-hover:bg-primary/20">
              <Zap className="h-6 w-6 text-primary" />
            </div>
            <h3 className="mb-1.5 text-sm font-semibold text-foreground">Instant Settlement</h3>
            <p className="text-center text-xs text-muted-foreground leading-relaxed">
              Fast order matching with real-time transactions
            </p>
          </CardContent>
        </Card>
        <Card className="group border-border/50 bg-card/50 backdrop-blur transition-all hover:border-primary/30 hover:bg-card">
          <CardContent className="flex flex-col items-center p-6">
            <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-xl bg-primary/10 transition-colors group-hover:bg-primary/20">
              <Users className="h-6 w-6 text-primary" />
            </div>
            <h3 className="mb-1.5 text-sm font-semibold text-foreground">Peer-to-Peer</h3>
            <p className="text-center text-xs text-muted-foreground leading-relaxed">
              Direct lending without intermediaries
            </p>
          </CardContent>
        </Card>
      </div>
      <div className="mt-10 flex items-center gap-2 text-sm text-muted-foreground">
        <span>Click the Connect button above to get started</span>
        <ArrowRight className="h-4 w-4" />
      </div>
    </div>
  )
}

export function HomeContent() {
  const { isConnected } = useAccount()

  return (
    <div className="min-h-screen bg-background">
      <Header />
      
      <main className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        {!isConnected ? (
          <ConnectionPrompt />
        ) : (
          <div className="space-y-8">
            <div className="border-b border-border pb-6">
              <h1 className="text-2xl font-bold tracking-tight text-foreground">Dashboard</h1>
              <p className="mt-1 text-sm text-muted-foreground">Manage your lending and borrowing positions</p>
            </div>

            <div className="grid gap-6 lg:grid-cols-12">
              <div className="space-y-6 lg:col-span-4">
                <LenderPanel />
                <BorrowerPanel />
              </div>

              <div className="lg:col-span-4">
                <ActionsPanel />
              </div>

              <div className="lg:col-span-4">
                <Dashboard />
              </div>
            </div>
          </div>
        )}
      </main>

      <footer className="mt-auto border-t border-border bg-card/30">
        <div className="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
          <div className="flex flex-col items-center justify-between gap-4 sm:flex-row">
            <div className="flex items-center gap-3">
              <div className="flex h-7 w-7 items-center justify-center rounded-md bg-primary/10">
                <Wallet className="h-4 w-4 text-primary" />
              </div>
              <span className="text-sm font-medium text-foreground">P2P Lending Protocol</span>
            </div>
            <div className="flex items-center gap-6 text-xs text-muted-foreground">
              <span>Powered by Aave Integration</span>
              <span className="flex items-center gap-1.5">
                <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-chart-3" />
                Connected to Anvil
              </span>
            </div>
          </div>
        </div>
      </footer>
    </div>
  )
}
