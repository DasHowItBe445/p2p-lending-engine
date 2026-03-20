'use client'

import { useWriteContract, useWaitForTransactionReceipt, useReadContract, useAccount } from 'wagmi'
import { parseUnits } from 'viem'
import { 
  MOCK_ERC20_ADDRESS, 
  P2P_LENDING_ADDRESS, 
  ERC20_ABI, 
  P2P_LENDING_ABI 
} from '@/lib/contracts'

// Hook for approving tokens
export function useApproveTokens() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const approve = async (amount: string) => {
    const parsedAmount = parseUnits(amount, 18)
    writeContract({
      address: MOCK_ERC20_ADDRESS,
      abi: ERC20_ABI,
      functionName: 'approve',
      args: [P2P_LENDING_ADDRESS, parsedAmount],
    })
  }

  return {
    approve,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  }
}

// Hook for placing lender orders
export function usePlaceLenderOrder() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const placeLenderOrder = async (amount: string, interestRate: string) => {
    const parsedAmount = parseUnits(amount, 18)
    const parsedRate = BigInt(Math.floor(parseFloat(interestRate) * 100)) // Convert to basis points
    writeContract({
      address: P2P_LENDING_ADDRESS,
      abi: P2P_LENDING_ABI,
      functionName: 'placeLenderOrder',
      args: [parsedAmount, parsedRate],
    })
  }

  return {
    placeLenderOrder,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  }
}

// Hook for placing borrow orders
export function usePlaceBorrowOrder() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const placeBorrowOrder = async (amount: string, interestRate: string) => {
    const parsedAmount = parseUnits(amount, 18)
    const parsedRate = BigInt(Math.floor(parseFloat(interestRate) * 100)) // Convert to basis points
    writeContract({
      address: P2P_LENDING_ADDRESS,
      abi: P2P_LENDING_ABI,
      functionName: 'placeBorrowOrder',
      args: [parsedAmount, parsedRate],
    })
  }

  return {
    placeBorrowOrder,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  }
}

// Hook for matching orders
export function useMatchOrders() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const matchOrders = async (lenderOrderId: string) => {
    writeContract({
      address: P2P_LENDING_ADDRESS,
      abi: P2P_LENDING_ABI,
      functionName: 'matchOrders',
      args: [BigInt(lenderOrderId)],
    })
  }

  return {
    matchOrders,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  }
}

// Hook for repaying loans
export function useRepayLoan() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const repay = async (loanId: string) => {
    writeContract({
      address: P2P_LENDING_ADDRESS,
      abi: P2P_LENDING_ABI,
      functionName: 'repay',
      args: [BigInt(loanId)],
    })
  }

  return {
    repay,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  }
}

// Hook for withdrawing funds
export function useWithdraw() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const withdraw = async () => {
    writeContract({
      address: P2P_LENDING_ADDRESS,
      abi: P2P_LENDING_ABI,
      functionName: 'withdraw',
      args: [],
    })
  }

  return {
    withdraw,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  }
}

// Hook for reading order counts
export function useOrderCounts() {
  const { data: lenderOrderCount } = useReadContract({
    address: P2P_LENDING_ADDRESS,
    abi: P2P_LENDING_ABI,
    functionName: 'lenderOrderCount',
  })

  const { data: borrowOrderCount } = useReadContract({
    address: P2P_LENDING_ADDRESS,
    abi: P2P_LENDING_ABI,
    functionName: 'borrowOrderCount',
  })

  const { data: loanCount } = useReadContract({
    address: P2P_LENDING_ADDRESS,
    abi: P2P_LENDING_ABI,
    functionName: 'loanCount',
  })

  return {
    lenderOrderCount: lenderOrderCount ? Number(lenderOrderCount) : 0,
    borrowOrderCount: borrowOrderCount ? Number(borrowOrderCount) : 0,
    loanCount: loanCount ? Number(loanCount) : 0,
  }
}

// Hook for reading token allowance
export function useTokenAllowance() {
  const { address } = useAccount()

  const { data: allowance, refetch } = useReadContract({
    address: MOCK_ERC20_ADDRESS,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: address ? [address, P2P_LENDING_ADDRESS] : undefined,
    query: {
      enabled: !!address,
    },
  })

  return {
    allowance: allowance || BigInt(0),
    refetch,
  }
}
