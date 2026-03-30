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

  const approve = async () => {
    writeContract({
      address: MOCK_ERC20_ADDRESS,
      abi: ERC20_ABI,
      functionName: 'approve',
      args: [
        P2P_LENDING_ADDRESS,
        BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
      ],
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
    try {
      console.log("LENDER ORDER DEBUG")
      console.log("Amount:", parsedAmount.toString())
      console.log("Rate:", parsedRate.toString())
      console.log("Contract:", P2P_LENDING_ADDRESS)
    
      writeContract({
        address: P2P_LENDING_ADDRESS,
        abi: P2P_LENDING_ABI,
        functionName: 'placeLenderOrder',
        args: [parsedAmount, parsedRate],
      })
    } catch (err) {
      console.error("Lender error:", err)
    }
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

  const matchOrders = async (maxItems: string) => {
    writeContract({
      address: P2P_LENDING_ADDRESS,
      abi: P2P_LENDING_ABI,
      functionName: 'matchOrders',
      args: [BigInt(maxItems)],
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
  const { data: nextLenderOrderId } = useReadContract({
    address: P2P_LENDING_ADDRESS,
    abi: P2P_LENDING_ABI,
    functionName: 'nextLenderOrderId',
  })

  const { data: nextBorrowOrderId } = useReadContract({
    address: P2P_LENDING_ADDRESS,
    abi: P2P_LENDING_ABI,
    functionName: 'nextBorrowOrderId',
  })

  const { data: nextLoanId } = useReadContract({
    address: P2P_LENDING_ADDRESS,
    abi: P2P_LENDING_ABI,
    functionName: 'nextLoanId',
  })

  return {
    // nextId starts at 1, so the first valid id is 1 and "count" is nextId - 1
    lenderOrderCount: nextLenderOrderId ? Math.max(0, Number(nextLenderOrderId) - 1) : 0,
    borrowOrderCount: nextBorrowOrderId ? Math.max(0, Number(nextBorrowOrderId) - 1) : 0,
    loanCount: nextLoanId ? Math.max(0, Number(nextLoanId) - 1) : 0,
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