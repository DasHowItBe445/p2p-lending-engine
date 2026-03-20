'use client'

import { useState, useEffect } from 'react'
import { useAccount, useReadContract } from 'wagmi'
import { toast } from 'sonner'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { Field, FieldGroup, FieldLabel } from '@/components/ui/field'
import { useMatchOrders, useRepayLoan, useWithdraw, useApproveTokens, useTokenAllowance } from '@/hooks/use-lending-contract'
import { P2P_LENDING_ADDRESS, P2P_LENDING_ABI } from '@/lib/contracts'
import { ArrowLeftRight, CreditCard, Wallet, ExternalLink, CheckCircle } from 'lucide-react'
import { formatUnits } from 'viem'

export function ActionsPanel() {
  const { isConnected } = useAccount()
  const [maxItems, setMaxItems] = useState('1')
  const [loanId, setLoanId] = useState('')

  // Hooks
  const { matchOrders, hash: matchHash, isPending: isMatching, isConfirming: isMatchConfirming, isSuccess: isMatchSuccess, error: matchError } = useMatchOrders()
  const { repay, hash: repayHash, isPending: isRepaying, isConfirming: isRepayConfirming, isSuccess: isRepaySuccess, error: repayError } = useRepayLoan()
  const { withdraw, hash: withdrawHash, isPending: isWithdrawing, isConfirming: isWithdrawConfirming, isSuccess: isWithdrawSuccess, error: withdrawError } = useWithdraw()
  const { approve, hash: approveHash, isPending: isApproving, isConfirming: isApproveConfirming, isSuccess: isApproveSuccess } = useApproveTokens()
  const { allowance, refetch: refetchAllowance } = useTokenAllowance()

  const YEAR_SECONDS = BigInt(365) * BigInt(24) * BigInt(60) * BigInt(60)
  const BPS_DENOM = BigInt(10_000)
  const nowSeconds = BigInt(Math.floor(Date.now() / 1000))
  const ZERO = BigInt(0)

  const { data: loanPos } = useReadContract({
    address: P2P_LENDING_ADDRESS,
    abi: P2P_LENDING_ABI,
    functionName: 'loanPositions',
    args: loanId ? [BigInt(loanId)] : undefined,
    query: {
      enabled: !!loanId,
    },
  })

  const pos = loanPos as
    | {
        lender: string
        borrower: string
        principal: bigint
        rateBps: number
        startTime: number
      }
    | undefined

  const isLoanActive =
    !!pos && pos.lender !== '0x0000000000000000000000000000000000000000' && pos.principal > ZERO

  const elapsed = isLoanActive
    ? nowSeconds > BigInt(pos!.startTime)
      ? nowSeconds - BigInt(pos!.startTime)
      : ZERO
    : ZERO
  const interest = isLoanActive
    ? (pos!.principal * BigInt(pos!.rateBps) * elapsed) / (BPS_DENOM * YEAR_SECONDS)
    : ZERO
  const totalOwed = isLoanActive ? pos!.principal + interest : ZERO

  const totalOwedHuman = totalOwed > ZERO ? formatUnits(totalOwed, 18) : ''
  const hasAllowance = allowance >= totalOwed && totalOwed > ZERO

  // Success handlers
  useEffect(() => {
    if (isMatchSuccess) {
      toast.success('Orders matched successfully!', {
        description: matchHash ? `Transaction: ${matchHash.slice(0, 10)}...` : undefined,
      })
      setMaxItems('1')
    }
  }, [isMatchSuccess, matchHash])

  useEffect(() => {
    if (isRepaySuccess) {
      toast.success('Loan repaid successfully!', {
        description: repayHash ? `Transaction: ${repayHash.slice(0, 10)}...` : undefined,
      })
      setLoanId('')
    }
  }, [isRepaySuccess, repayHash])

  useEffect(() => {
    if (isWithdrawSuccess) {
      toast.success('Funds withdrawn successfully!', {
        description: withdrawHash ? `Transaction: ${withdrawHash.slice(0, 10)}...` : undefined,
      })
    }
  }, [isWithdrawSuccess, withdrawHash])

  useEffect(() => {
    if (isApproveSuccess) {
      toast.success('Tokens approved for repayment!', {
        description: approveHash ? `Transaction: ${approveHash.slice(0, 10)}...` : undefined,
      })
      refetchAllowance()
    }
  }, [isApproveSuccess, approveHash, refetchAllowance])

  // Error handlers
  useEffect(() => {
    if (matchError) toast.error('Match failed', { description: matchError.message.slice(0, 100) })
  }, [matchError])

  useEffect(() => {
    if (repayError) toast.error('Repayment failed', { description: repayError.message.slice(0, 100) })
  }, [repayError])

  useEffect(() => {
    if (withdrawError) toast.error('Withdrawal failed', { description: withdrawError.message.slice(0, 100) })
  }, [withdrawError])

  const handleMatch = async () => {
    if (!maxItems) {
      toast.error('Please enter max items')
      return
    }
    await matchOrders(maxItems)
  }

  const handleApproveRepay = async () => {
    if (!totalOwedHuman) {
      toast.error('Enter a valid loan ID')
      return
    }
    await approve(totalOwedHuman)
  }

  const handleRepay = async () => {
    if (!loanId) {
      toast.error('Please enter a loan ID')
      return
    }
    await repay(loanId)
  }

  const handleWithdraw = async () => {
    await withdraw()
  }

  const latestHash = matchHash || repayHash || withdrawHash || approveHash

  return (
    <div className="space-y-6">
      {/* Order Matching */}
      <Card className="border-border bg-card">
        <CardHeader className="pb-4">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
              <ArrowLeftRight className="h-5 w-5 text-accent" />
            </div>
            <div>
              <CardTitle className="text-lg font-semibold text-card-foreground">Order Matching</CardTitle>
              <CardDescription className="text-muted-foreground">Match your borrow order with a lender</CardDescription>
            </div>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          <Field>
            <FieldLabel className="text-muted-foreground">Max Items</FieldLabel>
            <Input
              type="number"
              placeholder="1"
              value={maxItems}
              onChange={(e) => setMaxItems(e.target.value)}
              className="bg-secondary border-border text-foreground placeholder:text-muted-foreground"
              disabled={!isConnected}
            />
          </Field>
          <Button
            className="w-full bg-accent text-accent-foreground hover:bg-accent/90"
            onClick={handleMatch}
            disabled={!isConnected || isMatching || isMatchConfirming || !maxItems}
          >
            {isMatching || isMatchConfirming ? (
              <>
                <Spinner className="mr-2 h-4 w-4" />
                {isMatchConfirming ? 'Confirming...' : 'Matching...'}
              </>
            ) : (
              'Match Orders'
            )}
          </Button>
        </CardContent>
      </Card>

      {/* Loan Repayment */}
      <Card className="border-border bg-card">
        <CardHeader className="pb-4">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-success/10">
              <CreditCard className="h-5 w-5 text-success" />
            </div>
            <div>
              <CardTitle className="text-lg font-semibold text-card-foreground">Loan Repayment</CardTitle>
              <CardDescription className="text-muted-foreground">Repay your active loans</CardDescription>
            </div>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          <FieldGroup>
            <Field>
              <FieldLabel className="text-muted-foreground">Loan ID</FieldLabel>
              <Input
                type="number"
                placeholder="0"
                value={loanId}
                onChange={(e) => setLoanId(e.target.value)}
                className="bg-secondary border-border text-foreground placeholder:text-muted-foreground"
                disabled={!isConnected}
              />
            </Field>
          </FieldGroup>

          {isLoanActive && (
            <div className="rounded-lg border border-border bg-secondary/20 p-3">
              <p className="text-xs text-muted-foreground">Total due (principal + interest)</p>
              <p className="mt-1 text-sm font-medium text-foreground">
                {Number(formatUnits(totalOwed, 18)).toLocaleString(undefined, {
                  maximumFractionDigits: 4,
                })}{' '}
                TOKEN
              </p>
            </div>
          )}
          <div className="flex flex-col gap-3">
            <Button
              variant="outline"
              className="w-full border-border bg-secondary text-foreground hover:bg-secondary/80"
              onClick={handleApproveRepay}
              disabled={!isConnected || isApproving || isApproveConfirming || !totalOwedHuman}
            >
              {isApproving || isApproveConfirming ? (
                <>
                  <Spinner className="mr-2 h-4 w-4" />
                  {isApproveConfirming ? 'Confirming...' : 'Approving...'}
                </>
              ) : hasAllowance ? (
                <>
                  <CheckCircle className="mr-2 h-4 w-4 text-primary" />
                  Approved
                </>
              ) : (
                'Approve Repayment'
              )}
            </Button>
            <Button
              className="w-full bg-success text-background hover:bg-success/90"
              onClick={handleRepay}
              disabled={!isConnected || isRepaying || isRepayConfirming || !loanId || !hasAllowance}
            >
              {isRepaying || isRepayConfirming ? (
                <>
                  <Spinner className="mr-2 h-4 w-4" />
                  {isRepayConfirming ? 'Confirming...' : 'Repaying...'}
                </>
              ) : (
                'Repay Loan'
              )}
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Withdraw */}
      <Card className="border-border bg-card">
        <CardHeader className="pb-4">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
              <Wallet className="h-5 w-5 text-primary" />
            </div>
            <div>
              <CardTitle className="text-lg font-semibold text-card-foreground">Withdraw Funds</CardTitle>
              <CardDescription className="text-muted-foreground">Withdraw your available balance</CardDescription>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <Button
            className="w-full bg-primary text-primary-foreground hover:bg-primary/90"
            onClick={handleWithdraw}
            disabled={!isConnected || isWithdrawing || isWithdrawConfirming}
          >
            {isWithdrawing || isWithdrawConfirming ? (
              <>
                <Spinner className="mr-2 h-4 w-4" />
                {isWithdrawConfirming ? 'Confirming...' : 'Withdrawing...'}
              </>
            ) : (
              'Withdraw Funds'
            )}
          </Button>
        </CardContent>
      </Card>

      {/* Transaction Hash Display */}
      {latestHash && (
        <div className="rounded-lg border border-border bg-card p-4">
          <p className="text-xs text-muted-foreground">Latest Transaction</p>
          <div className="mt-1 flex items-center gap-2">
            <code className="text-sm text-primary">{latestHash.slice(0, 30)}...</code>
            <ExternalLink className="h-3 w-3 text-muted-foreground" />
          </div>
        </div>
      )}
    </div>
  )
}
