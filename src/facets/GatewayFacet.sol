// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.24;

import { AppStorage, LibAppStorage } from "src/libs/LibAppStorage.sol";
import { LibErrors } from "src/libs/LibErrors.sol";
import { LibAuth } from "src/libs/LibAuth.sol";
import { LibUsdcToken } from "src/libs/LibUsdcToken.sol";
import { LibToken } from "src/libs/LibToken.sol";
import { AuthSignature } from "src/shared/Structs.sol";
import { ReentrancyGuard } from "src/shared/ReentrancyGuard.sol";
import { IDexSwapAdapter } from "src/interfaces/IDexSwapAdapter.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract GatewayFacet is ReentrancyGuard {
  event TriballyGatewayDeposit(
    address indexed user,
    address indexed depositToken,
    uint256 depositAmount,
    uint256 usdcAmount
  );

  event TriballyGatewayWithdraw(address user, uint amount);

  function gatewayPoolBalance() external view returns (uint) {
    return LibAppStorage.diamondStorage().gatewayPoolBalance;
  }

  function deposit(
    address _user,
    address _token,
    uint256 _amount,
    uint256 _minUsdcAmount,
    bytes calldata _swapData
  ) external payable {
    AppStorage storage s = LibAppStorage.diamondStorage();

    bool isNative = _token == address(0);

    if (isNative) {
      if (msg.value != _amount) {
        revert LibErrors.InvalidInputs();
      }
    } else {
      LibToken.transferFrom(_token, msg.sender, _amount);
    }

    uint256 usdcAmount;

    if (_token == s.usdcToken) {
      usdcAmount = _amount;
    } else {
      if (!isNative) {
        uint256 currentAllowance = IERC20(_token).allowance(address(this), s.swapAdapter);
        if (currentAllowance < _amount) {
          IERC20(_token).approve(s.swapAdapter, type(uint256).max);
        }
      }

      usdcAmount = IDexSwapAdapter(s.swapAdapter).swap{ value: isNative ? _amount : 0 }(
        _token,
        _amount,
        _minUsdcAmount,
        _swapData
      );

      if (usdcAmount < _minUsdcAmount) {
        revert LibErrors.InsufficientUsdcReceived(usdcAmount, _minUsdcAmount);
      }
    }

    s.gatewayPoolBalance += usdcAmount;

    emit TriballyGatewayDeposit(_user, _token, _amount, usdcAmount);
  }

  function calculateUsdc(address _token, uint256 _amount, bytes calldata _swapData) external returns (uint256) {
    AppStorage storage s = LibAppStorage.diamondStorage();

    if (_token == s.usdcToken) {
      return _amount;
    }

    return IDexSwapAdapter(s.swapAdapter).getQuote(_token, _amount, _swapData);
  }

  function withdraw(address _user, uint _amount,  AuthSignature calldata _sig) external nonReentrant {
    AppStorage storage s = LibAppStorage.diamondStorage();

    LibAuth.assertValidSignature(msg.sender, s.signer, _sig, abi.encodePacked(_user, _amount));

    if (s.gatewayPoolBalance < _amount) {
      revert LibErrors.InsufficientBalanceError();
    }

    s.gatewayPoolBalance -= _amount;

    LibUsdcToken.transferTo(_user, _amount);

    emit TriballyGatewayWithdraw(_user, _amount);
  }
}
