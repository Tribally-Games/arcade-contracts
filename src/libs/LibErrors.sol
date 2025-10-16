// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.24;

library LibErrors {
  error InvalidInputs();

  error InvalidSignerError();

  error CallerMustBeAdminError();

  error InsufficientBalanceError();

  error InvalidTribalTokenError();

  error SignatureExpired(address caller);

  error SignatureInvalid(address caller);

  error SignatureAlreadyUsed(address caller);

  error AmountMustBeGreaterThanZero();

  error TransferFailed();
}
