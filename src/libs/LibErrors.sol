// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.24;

library LibErrors {
  error InvalidInputs();

  error InvalidSignerError();

  error CallerMustBeAdminError();

  error InsufficientBalanceError();

  error InvalidGovTokenError();

  error SignatureExpired(address caller);

  error SignatureInvalid(address caller);

  error SignatureAlreadyUsed(address caller);

  error AmountMustBeGreaterThanZero();

  error TransferFailed();

  error InsufficientUsdcReceived(uint256 received, uint256 minimum);

  error InvalidSwapAdapter();

  error SwapFailed();
}
