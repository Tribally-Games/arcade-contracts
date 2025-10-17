// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.24;

import { AppStorage, LibAppStorage } from "src/libs/LibAppStorage.sol";
import { LibErrors } from "src/libs/LibErrors.sol";
import { LibAuth } from "src/libs/LibAuth.sol";
import { LibTribalToken } from "src/libs/LibTribalToken.sol";
import { AuthSignature } from "src/shared/Structs.sol";
import { ReentrancyGuard } from "src/shared/ReentrancyGuard.sol";

contract GatewayFacet is ReentrancyGuard {
  event TriballyGatewayDeposit(address user, uint amount);

  event TriballyGatewayWithdraw(address user, uint amount);

  function gatewayPoolBalance() external view returns (uint) {
    return LibAppStorage.diamondStorage().gatewayPoolBalance;
  }

  function deposit(address _user, uint _amount) external {
    AppStorage storage s = LibAppStorage.diamondStorage();

    LibTribalToken.transferFrom(msg.sender, _amount);

    s.gatewayPoolBalance += _amount;

    emit TriballyGatewayDeposit(_user, _amount);
  }

  function withdraw(address _user, uint _amount,  AuthSignature calldata _sig) external nonReentrant {
    AppStorage storage s = LibAppStorage.diamondStorage();

    LibAuth.assertValidSignature(msg.sender, s.signer, _sig, abi.encodePacked(_user, _amount));

    if (s.gatewayPoolBalance < _amount) {
      revert LibErrors.InsufficientBalanceError();
    }

    s.gatewayPoolBalance -= _amount;

    LibTribalToken.transferTo(_user, _amount);

    emit TriballyGatewayWithdraw(_user, _amount);
  }
}
