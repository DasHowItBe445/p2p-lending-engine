'use client'

import { useEffect } from 'react'
import { useReadContracts } from 'wagmi'
import { formatUnits } from 'viem'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { Empty } from '@/components/ui/empty'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { P2P_LENDING_ADDRESS, P2P_LENDING_ABI } from '@/lib/contracts'
import { useOrderCounts } from '@/hooks/use-lending-contract'
import { FileText, TrendingUp, TrendingDown, Banknote, Clock, CheckCircle, XCircle } from 'lucide-react'

interface LenderOrder {
  owner: string
  amount: bigint
  minRateBps: number
  createdAt: number
  remaining: bigint
}

interface BorrowOrder {
  owner: string
  amount: bigint
  maxRateBps: number
  createdAt: number
  remaining: bigint
}

interface LoanPosition {
  lender: string
  borrower: string
  principal: bigint
  rateBps: number
  startTime: number
}

interface Loan extends LoanPosition {
  repaymentAmount: bigint
  isRepaid: boolean
}

function OrderCard({ 
  type, 
  id, 
  address, 
  amount, 
  rate, 
  isActive, 
  isMatched 
}: { 
  type: 'lender' | 'borrower'
  id: number
  address: string
  amount: bigint
  rate: bigint
  isActive: boolean
  isMatched: boolean
}) {
  const Icon = type === 'lender' ? TrendingUp : TrendingDown
  const iconColor = type === 'lender' ? 'text-primary' : 'text-chart-4'
  const bgColor = type === 'lender' ? 'bg-primary/10' : 'bg-chart-4/10'

  return (
    <div className="rounded-lg border border-border bg-secondary/30 p-4">
      <div className="flex items-start justify-between">
        <div className="flex items-center gap-3">
          <div className={`flex h-10 w-10 items-center justify-center rounded-lg ${bgColor}`}>
            <Icon className={`h-5 w-5 ${iconColor}`} />
          </div>
          <div>
            <p className="text-sm font-medium text-foreground">Order #{id}</p>
            <p className="text-xs text-muted-foreground">
              {address.slice(0, 6)}...{address.slice(-4)}
            </p>
          </div>
        </div>
        <div className="flex gap-2">
          {isMatched ? (
            <Badge variant="outline" className="border-chart-3/50 bg-chart-3/10 text-chart-3">
              Matched
            </Badge>
          ) : isActive ? (
            <Badge variant="outline" className="border-primary/50 bg-primary/10 text-primary">
              Active
            </Badge>
          ) : (
            <Badge variant="outline" className="border-muted-foreground/50 bg-muted/50 text-muted-foreground">
              Inactive
            </Badge>
          )}
        </div>
      </div>
      <div className="mt-4 grid grid-cols-2 gap-4">
        <div>
          <p className="text-xs text-muted-foreground">Amount</p>
          <p className="text-sm font-medium text-foreground">
            {Number(formatUnits(amount, 18)).toLocaleString(undefined, { maximumFractionDigits: 4 })} TOKEN
          </p>
        </div>
        <div>
          <p className="text-xs text-muted-foreground">Interest Rate</p>
          <p className="text-sm font-medium text-foreground">{Number(rate) / 100}%</p>
        </div>
      </div>
    </div>
  )
}

function LoanCard({ 
  id, 
  loan 
}: { 
  id: number
  loan: Loan
}) {
  return (
    <div className="rounded-lg border border-border bg-secondary/30 p-4">
      <div className="flex items-start justify-between">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-chart-3/10">
            <Banknote className="h-5 w-5 text-chart-3" />
          </div>
          <div>
            <p className="text-sm font-medium text-foreground">Loan #{id}</p>
            <p className="text-xs text-muted-foreground">
              {new Date(Number(loan.startTime) * 1000).toLocaleDateString()}
            </p>
          </div>
        </div>
        {loan.isRepaid ? (
          <Badge variant="outline" className="border-chart-3/50 bg-chart-3/10 text-chart-3">
            <CheckCircle className="mr-1 h-3 w-3" />
            Repaid
          </Badge>
        ) : (
          <Badge variant="outline" className="border-primary/50 bg-primary/10 text-primary">
            <Clock className="mr-1 h-3 w-3" />
            Active
          </Badge>
        )}
      </div>
      <div className="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-4">
        <div>
          <p className="text-xs text-muted-foreground">Lender</p>
          <p className="text-sm font-medium text-foreground">
            {loan.lender.slice(0, 6)}...{loan.lender.slice(-4)}
          </p>
        </div>
        <div>
          <p className="text-xs text-muted-foreground">Borrower</p>
          <p className="text-sm font-medium text-foreground">
            {loan.borrower.slice(0, 6)}...{loan.borrower.slice(-4)}
          </p>
        </div>
        <div>
          <p className="text-xs text-muted-foreground">Amount</p>
          <p className="text-sm font-medium text-foreground">
            {Number(formatUnits(loan.principal, 18)).toLocaleString(undefined, { maximumFractionDigits: 4 })}
          </p>
        </div>
        <div>
          <p className="text-xs text-muted-foreground">Repayment</p>
          <p className="text-sm font-medium text-foreground">
            {Number(formatUnits(loan.repaymentAmount, 18)).toLocaleString(undefined, { maximumFractionDigits: 4 })}
          </p>
        </div>
      </div>
    </div>
  )
}

export function Dashboard() {
  const { lenderOrderCount, borrowOrderCount, loanCount } = useOrderCounts()

  const YEAR_SECONDS = BigInt(365) * BigInt(24) * BigInt(60) * BigInt(60)
  const BPS_DENOM = BigInt(10_000)
  const nowSeconds = BigInt(Math.floor(Date.now() / 1000))
  const ZERO = BigInt(0)

  // Create read calls for all lender orders
  const lenderOrderCalls = Array.from({ length: lenderOrderCount }, (_, i) => ({
    address: P2P_LENDING_ADDRESS,
    abi: P2P_LENDING_ABI,
    functionName: 'lenderOrders' as const,
    args: [BigInt(i + 1)],
  }))

  // Create read calls for all borrower orders
  const borrowOrderCalls = Array.from({ length: borrowOrderCount }, (_, i) => ({
    address: P2P_LENDING_ADDRESS,
    abi: P2P_LENDING_ABI,
    functionName: 'borrowOrders' as const,
    args: [BigInt(i + 1)],
  }))

  // Create read calls for all loans
  const loanCalls = Array.from({ length: loanCount }, (_, i) => ({
    address: P2P_LENDING_ADDRESS,
    abi: P2P_LENDING_ABI,
    functionName: 'loanPositions' as const,
    args: [BigInt(i + 1)],
  }))

  const { 
    data: lenderOrders, 
    isLoading: isLoadingLenderOrders,
    refetch: refetchLenderOrders
  } = useReadContracts({
    contracts: lenderOrderCalls,
    query: {
      enabled: lenderOrderCount > 0,
    },
  })

  const { data: borrowOrders, isLoading: isLoadingBorrowOrders, refetch: refetchBorrowOrders } = useReadContracts({
    contracts: borrowOrderCalls,
    query: {
      enabled: borrowOrderCount > 0,
    },
  })

  const { data: loans, isLoading: isLoadingLoans, refetch: refetchLoans } = useReadContracts({
    contracts: loanCalls,
    query: {
      enabled: loanCount > 0,
    },
  })

  const isLoading = isLoadingLenderOrders || isLoadingBorrowOrders || isLoadingLoans

  // Filter active lender orders
  const activeLenderOrders = lenderOrders?.filter(
    (result) =>
      result.status === 'success' &&
      (result.result as LenderOrder)?.owner !== '0x0000000000000000000000000000000000000000' &&
      (result.result as LenderOrder)?.remaining > ZERO
  ) || []

  // Filter active borrow orders
  const activeBorrowOrders = borrowOrders?.filter(
    (result) =>
      result.status === 'success' &&
      (result.result as BorrowOrder)?.owner !== '0x0000000000000000000000000000000000000000' &&
      (result.result as BorrowOrder)?.remaining > ZERO
  ) || []

  // Filter active loans (not repaid)
  const activeLoans = loans?.filter(
    (result) =>
      result.status === 'success' &&
      (result.result as LoanPosition)?.lender !== '0x0000000000000000000000000000000000000000' &&
      (result.result as LoanPosition)?.principal > ZERO
  ) || []

  useEffect(() => {
    const interval = setInterval(() => {
      refetchLenderOrders()
      refetchBorrowOrders()
      refetchLoans()
    }, 3000)
  
    return () => clearInterval(interval)
  }, [])

  return (
    <Card className="border-border bg-card">
      <CardHeader>
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-muted">
            <FileText className="h-5 w-5 text-foreground" />
          </div>
          <div>
            <CardTitle className="text-lg font-semibold text-card-foreground">Dashboard</CardTitle>
            <CardDescription className="text-muted-foreground">Overview of all orders and loans</CardDescription>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        {/* Stats */}
        <div className="mb-6 grid grid-cols-3 gap-4">
          <div className="rounded-lg border border-border bg-secondary/50 p-4 text-center">
            <p className="text-2xl font-bold text-primary">{activeLenderOrders.length}</p>
            <p className="text-xs text-muted-foreground">Lender Orders</p>
          </div>
          <div className="rounded-lg border border-border bg-secondary/50 p-4 text-center">
            <p className="text-2xl font-bold text-chart-4">{activeBorrowOrders.length}</p>
            <p className="text-xs text-muted-foreground">Borrow Orders</p>
          </div>
          <div className="rounded-lg border border-border bg-secondary/50 p-4 text-center">
            <p className="text-2xl font-bold text-chart-3">{activeLoans.length}</p>
            <p className="text-xs text-muted-foreground">Active Loans</p>
          </div>
        </div>

        <Tabs defaultValue="lender-orders" className="w-full">
          <TabsList className="mb-4 grid w-full grid-cols-3 bg-secondary">
            <TabsTrigger value="lender-orders" className="data-[state=active]:bg-primary data-[state=active]:text-primary-foreground">
              Lender Orders
            </TabsTrigger>
            <TabsTrigger value="borrow-orders" className="data-[state=active]:bg-primary data-[state=active]:text-primary-foreground">
              Borrow Orders
            </TabsTrigger>
            <TabsTrigger value="loans" className="data-[state=active]:bg-primary data-[state=active]:text-primary-foreground">
              Loans
            </TabsTrigger>
          </TabsList>

          <TabsContent value="lender-orders" className="space-y-3">
            {isLoading ? (
              <div className="flex items-center justify-center py-8">
                <Spinner className="h-8 w-8" />
              </div>
            ) : lenderOrders && lenderOrders.length > 0 ? (
              lenderOrders.map((result, index) => {
                if (result.status !== 'success') return null
                const orderId = index + 1
                const order = result.result as LenderOrder
                const isActive = order.remaining > ZERO
                const isMatched = order.amount > ZERO && order.remaining < order.amount
                return (
                  <OrderCard
                    key={index}
                    type="lender"
                    id={orderId}
                    address={order.owner}
                    amount={order.amount}
                    rate={BigInt(order.minRateBps)}
                    isActive={isActive}
                    isMatched={isMatched}
                  />
                )
              })
            ) : (
              <Empty
                icon={TrendingUp}
                title="No lender orders"
                description="Place a lender order to see it here"
              />
            )}
          </TabsContent>

          <TabsContent value="borrow-orders" className="space-y-3">
            {isLoading ? (
              <div className="flex items-center justify-center py-8">
                <Spinner className="h-8 w-8" />
              </div>
            ) : borrowOrders && borrowOrders.length > 0 ? (
              borrowOrders.map((result, index) => {
                if (result.status !== 'success') return null
                const orderId = index + 1
                const order = result.result as BorrowOrder
                const isActive = order.remaining > ZERO
                const isMatched = order.amount > ZERO && order.remaining < order.amount
                return (
                  <OrderCard
                    key={index}
                    type="borrower"
                    id={orderId}
                    address={order.owner}
                    amount={order.amount}
                    rate={BigInt(order.maxRateBps)}
                    isActive={isActive}
                    isMatched={isMatched}
                  />
                )
              })
            ) : (
              <Empty
                icon={TrendingDown}
                title="No borrow orders"
                description="Place a borrow order to see it here"
              />
            )}
          </TabsContent>

          <TabsContent value="loans" className="space-y-3">
            {isLoading ? (
              <div className="flex items-center justify-center py-8">
                <Spinner className="h-8 w-8" />
              </div>
            ) : loans && loans.length > 0 ? (
              loans.map((result, index) => {
                if (result.status !== 'success') return null
                const loanId = index + 1
                const pos = result.result as LoanPosition
                const isRepaid =
                  pos.lender === '0x0000000000000000000000000000000000000000' || pos.principal === ZERO

                const elapsed = isRepaid
                  ? ZERO
                  : nowSeconds > BigInt(pos.startTime)
                    ? nowSeconds - BigInt(pos.startTime)
                    : ZERO
                const interest = isRepaid
                  ? ZERO
                  : (pos.principal * BigInt(pos.rateBps) * elapsed) / (BPS_DENOM * YEAR_SECONDS)
                const repaymentAmount = pos.principal + interest

                const loan: Loan = {
                  ...pos,
                  repaymentAmount,
                  isRepaid,
                }

                return <LoanCard key={index} id={loanId} loan={loan} />
              })
            ) : (
              <Empty
                icon={Banknote}
                title="No loans"
                description="Match orders to create a loan"
              />
            )}
          </TabsContent>
        </Tabs>
      </CardContent>
    </Card>
  )
}
