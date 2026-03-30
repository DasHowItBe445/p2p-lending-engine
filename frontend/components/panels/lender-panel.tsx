'use client'

import { useState, useEffect } from 'react'
import { useAccount } from 'wagmi'
import { parseUnits } from 'viem'
import { toast } from 'sonner'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { Field, FieldGroup, FieldLabel } from '@/components/ui/field'
import { useApproveTokens, usePlaceLenderOrder, useTokenAllowance } from '@/hooks/use-lending-contract'
import { TrendingUp, CheckCircle, ExternalLink } from 'lucide-react'

export function LenderPanel() {
  const { isConnected } = useAccount()
  const [amount, setAmount] = useState('')
  const [interestRate, setInterestRate] = useState('')

  const { approve, hash: approveHash, isPending: isApproving, isConfirming: isApproveConfirming, isSuccess: isApproveSuccess, error: approveError } = useApproveTokens()
  const { placeLenderOrder, hash: orderHash, isPending: isPlacing, isConfirming: isOrderConfirming, isSuccess: isOrderSuccess, error: orderError } = usePlaceLenderOrder()
  const { allowance, refetch: refetchAllowance } = useTokenAllowance()

  let parsedAmount = BigInt(0)
  try {
    if (amount) parsedAmount = parseUnits(amount, 18)
  } catch {
    parsedAmount = BigInt(0)
  }
  const hasAllowance = allowance >= parsedAmount

  useEffect(() => {
    if (isApproveSuccess) {
      toast.success('Tokens approved successfully!', {
        description: approveHash ? `Transaction: ${approveHash.slice(0, 10)}...` : undefined,
        action: approveHash ? {
          label: 'View',
          onClick: () => window.open(`https://etherscan.io/tx/${approveHash}`, '_blank'),
        } : undefined,
      })
      refetchAllowance()
    }
  }, [isApproveSuccess, approveHash, refetchAllowance])

  useEffect(() => {
    if (isOrderSuccess) {
      toast.success('Lender order placed successfully!', {
        description: orderHash ? `Transaction: ${orderHash.slice(0, 10)}...` : undefined,
        action: orderHash ? {
          label: 'View',
          onClick: () => window.open(`https://etherscan.io/tx/${orderHash}`, '_blank'),
        } : undefined,
      })
      setAmount('')
      setInterestRate('')
    }
  }, [isOrderSuccess, orderHash])

  useEffect(() => {
    if (approveError) {
      toast.error('Approval failed', {
        description: approveError.message.slice(0, 100),
      })
    }
  }, [approveError])

  useEffect(() => {
    if (orderError) {
      toast.error('Order placement failed', {
        description: orderError.message.slice(0, 100),
      })
    }
  }, [orderError])

  const handleApprove = async () => {
    if (!amount) {
      toast.error('Please enter an amount')
      return
    }
    await approve()
  }

  const handlePlaceOrder = async () => {
    if (!amount || !interestRate) {
      toast.error('Please fill in all fields')
      return
    }
    await placeLenderOrder(amount, interestRate)
  }

  return (
    <Card className="border-border bg-card">
      <CardHeader className="pb-4">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
            <TrendingUp className="h-5 w-5 text-primary" />
          </div>
          <div>
            <CardTitle className="text-lg font-semibold text-card-foreground">Lender Panel</CardTitle>
            <CardDescription className="text-muted-foreground">Provide liquidity and earn interest</CardDescription>
          </div>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        <FieldGroup>
          <Field>
            <FieldLabel className="text-muted-foreground">Amount</FieldLabel>
            <Input
              type="number"
              placeholder="0.00"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="bg-secondary border-border text-foreground placeholder:text-muted-foreground"
              disabled={!isConnected}
            />
          </Field>

          <Field>
            <FieldLabel className="text-muted-foreground">Interest Rate (%)</FieldLabel>
            <Input
              type="number"
              placeholder="5.0"
              step="0.1"
              value={interestRate}
              onChange={(e) => setInterestRate(e.target.value)}
              className="bg-secondary border-border text-foreground placeholder:text-muted-foreground"
              disabled={!isConnected}
            />
          </Field>
        </FieldGroup>

        <div className="flex flex-col gap-3 pt-2">
          <Button
            variant="outline"
            className="w-full border-border bg-secondary text-foreground hover:bg-secondary/80"
            onClick={handleApprove}
            disabled={!isConnected || isApproving || isApproveConfirming || !amount}
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
              'Approve Tokens'
            )}
          </Button>

          <Button
            className="w-full bg-primary text-primary-foreground hover:bg-primary/90"
            onClick={handlePlaceOrder}
            disabled={
              !isConnected ||
              isPlacing ||
              isOrderConfirming ||
              !hasAllowance
            }
          >
            {isPlacing || isOrderConfirming ? (
              <>
                <Spinner className="mr-2 h-4 w-4" />
                {isOrderConfirming ? 'Confirming...' : 'Placing Order...'}
              </>
            ) : (
              'Place Lender Order'
            )}
          </Button>
        </div>

        {(approveHash || orderHash) && (
          <div className="rounded-lg border border-border bg-secondary/50 p-3">
            <p className="text-xs text-muted-foreground">Latest Transaction</p>
            <div className="mt-1 flex items-center gap-2">
              <code className="text-xs text-primary">
                {(orderHash || approveHash)?.slice(0, 20)}...
              </code>
              <ExternalLink className="h-3 w-3 text-muted-foreground" />
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
