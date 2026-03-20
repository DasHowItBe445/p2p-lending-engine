'use client'

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
  lender: string
  amount: bigint
  interestRate: bigint
  isActive: boolean
  isMatched: boolean
}

interface BorrowOrder {
  borrower: string
  amount: bigint
  interestRate: bigint
  isActive: boolean
  isMatched: boolean
}

interface Loan {
  lender: string
  borrower: string
  amount: bigint
  interestRate: bigint
  repaymentAmount: bigint
  isRepaid: boolean
  createdAt: bigint
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
              {new Date(Number(loan.createdAt) * 1000).toLocaleDateString()}
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
            {Number(formatUnits(loan.amount, 18)).toLocaleString(undefined, { maximumFractionDigits: 4 })}
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

  // Create read calls for all lender orders
  const lenderOrderCalls = Array.from({ length: lenderOrderCount }, (_, i) => ({
    address: P2P_LENDING_ADDRESS,
    abi: P2P_LENDING_ABI,
    functionName: 'getLenderOrder' as const,
    args: [BigInt(i)],
  }))

  // Create read calls for all borrower orders
  const borrowOrderCalls = Array.from({ length: borrowOrderCount }, (_, i) => ({
    address: P2P_LENDING_ADDRESS,
    abi: P2P_LENDING_ABI,
    functionName: 'getBorrowOrder' as const,
    args: [BigInt(i)],
  }))

  // Create read calls for all loans
  const loanCalls = Array.from({ length: loanCount }, (_, i) => ({
    address: P2P_LENDING_ADDRESS,
    abi: P2P_LENDING_ABI,
    functionName: 'getLoan' as const,
    args: [BigInt(i)],
  }))

  const { data: lenderOrders, isLoading: isLoadingLenderOrders } = useReadContracts({
    contracts: lenderOrderCalls,
    query: {
      enabled: lenderOrderCount > 0,
    },
  })

  const { data: borrowOrders, isLoading: isLoadingBorrowOrders } = useReadContracts({
    contracts: borrowOrderCalls,
    query: {
      enabled: borrowOrderCount > 0,
    },
  })

  const { data: loans, isLoading: isLoadingLoans } = useReadContracts({
    contracts: loanCalls,
    query: {
      enabled: loanCount > 0,
    },
  })

  const isLoading = isLoadingLenderOrders || isLoadingBorrowOrders || isLoadingLoans

  // Filter active lender orders
  const activeLenderOrders = lenderOrders?.filter(
    (result) => result.status === 'success' && (result.result as LenderOrder)?.isActive
  ) || []

  // Filter active borrow orders
  const activeBorrowOrders = borrowOrders?.filter(
    (result) => result.status === 'success' && (result.result as BorrowOrder)?.isActive
  ) || []

  // Filter active loans (not repaid)
  const activeLoans = loans?.filter(
    (result) => result.status === 'success' && !(result.result as Loan)?.isRepaid
  ) || []

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
                const order = result.result as LenderOrder
                return (
                  <OrderCard
                    key={index}
                    type="lender"
                    id={index}
                    address={order.lender}
                    amount={order.amount}
                    rate={order.interestRate}
                    isActive={order.isActive}
                    isMatched={order.isMatched}
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
                const order = result.result as BorrowOrder
                return (
                  <OrderCard
                    key={index}
                    type="borrower"
                    id={index}
                    address={order.borrower}
                    amount={order.amount}
                    rate={order.interestRate}
                    isActive={order.isActive}
                    isMatched={order.isMatched}
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
                const loan = result.result as Loan
                return <LoanCard key={index} id={index} loan={loan} />
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
