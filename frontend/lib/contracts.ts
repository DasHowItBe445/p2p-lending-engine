import { type Address } from 'viem'

// Contract addresses - Replace these with your deployed contract addresses
export const MOCK_ERC20_ADDRESS: Address = '0x5FbDB2315678afecb367f032d93F642f64180aa3'
export const P2P_LENDING_ADDRESS: Address = '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512'

// ERC20 ABI (Standard + Approve)
export const ERC20_ABI = [
  {
    name: 'name',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'string' }],
  },
  {
    name: 'symbol',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'string' }],
  },
  {
    name: 'decimals',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint8' }],
  },
  {
    name: 'balanceOf',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'allowance',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'approve',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [{ type: 'bool' }],
  },
  {
    name: 'transfer',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'to', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [{ type: 'bool' }],
  },
] as const

// P2P Lending Contract ABI
export const P2P_LENDING_ABI = [
  // Lender functions
  {
    name: 'placeLenderOrder',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'amount', type: 'uint256' },
      { name: 'interestRate', type: 'uint256' },
    ],
    outputs: [{ type: 'uint256' }],
  },
  // Borrower functions
  {
    name: 'placeBorrowOrder',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'amount', type: 'uint256' },
      { name: 'interestRate', type: 'uint256' },
    ],
    outputs: [{ type: 'uint256' }],
  },
  // Matching function
  {
    name: 'matchOrders',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'lenderOrderId', type: 'uint256' }],
    outputs: [{ type: 'uint256' }],
  },
  // Repayment function
  {
    name: 'repay',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'loanId', type: 'uint256' }],
    outputs: [],
  },
  // Withdraw function
  {
    name: 'withdraw',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [],
    outputs: [],
  },
  // View functions
  {
    name: 'getLenderOrder',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'orderId', type: 'uint256' }],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'lender', type: 'address' },
          { name: 'amount', type: 'uint256' },
          { name: 'interestRate', type: 'uint256' },
          { name: 'isActive', type: 'bool' },
          { name: 'isMatched', type: 'bool' },
        ],
      },
    ],
  },
  {
    name: 'getBorrowOrder',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'orderId', type: 'uint256' }],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'borrower', type: 'address' },
          { name: 'amount', type: 'uint256' },
          { name: 'interestRate', type: 'uint256' },
          { name: 'isActive', type: 'bool' },
          { name: 'isMatched', type: 'bool' },
        ],
      },
    ],
  },
  {
    name: 'getLoan',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'loanId', type: 'uint256' }],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'lender', type: 'address' },
          { name: 'borrower', type: 'address' },
          { name: 'amount', type: 'uint256' },
          { name: 'interestRate', type: 'uint256' },
          { name: 'repaymentAmount', type: 'uint256' },
          { name: 'isRepaid', type: 'bool' },
          { name: 'createdAt', type: 'uint256' },
        ],
      },
    ],
  },
  {
    name: 'lenderOrderCount',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'borrowOrderCount',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'loanCount',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint256' }],
  },
  // Events
  {
    name: 'LenderOrderPlaced',
    type: 'event',
    inputs: [
      { name: 'orderId', type: 'uint256', indexed: true },
      { name: 'lender', type: 'address', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
      { name: 'interestRate', type: 'uint256', indexed: false },
    ],
  },
  {
    name: 'BorrowOrderPlaced',
    type: 'event',
    inputs: [
      { name: 'orderId', type: 'uint256', indexed: true },
      { name: 'borrower', type: 'address', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
      { name: 'interestRate', type: 'uint256', indexed: false },
    ],
  },
  {
    name: 'OrdersMatched',
    type: 'event',
    inputs: [
      { name: 'loanId', type: 'uint256', indexed: true },
      { name: 'lenderOrderId', type: 'uint256', indexed: true },
      { name: 'borrowOrderId', type: 'uint256', indexed: true },
    ],
  },
  {
    name: 'LoanRepaid',
    type: 'event',
    inputs: [
      { name: 'loanId', type: 'uint256', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
    ],
  },
] as const
