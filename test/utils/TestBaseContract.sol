// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import { ECDSA } from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import { ERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { AuthSignature } from "src/shared/Structs.sol";
import { LibAuth } from "src/libs/LibAuth.sol";
import { Diamond } from "lib/diamond-2-hardhat/contracts/Diamond.sol";
import { DiamondCutFacet } from "lib/diamond-2-hardhat/contracts/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "lib/diamond-2-hardhat/contracts/facets/DiamondLoupeFacet.sol";
import { OwnershipFacet } from "lib/diamond-2-hardhat/contracts/facets/OwnershipFacet.sol";
import { IDiamondCut } from "lib/diamond-2-hardhat/contracts/interfaces/IDiamondCut.sol";
import { GatewayFacet } from "src/facets/GatewayFacet.sol";
import { SigningFacet } from "src/facets/SigningFacet.sol";
import { ConfigFacet } from "src/facets/ConfigFacet.sol";
import { InitDiamond } from "src/init/InitDiamond.sol";
import { DummyDexDepositor } from "src/depositors/DummyDexDepositor.sol";
import { MockWETH } from "src/mocks/MockWETH.sol";

contract MockERC20 is ERC20 {
  constructor() ERC20("MockERC20", "MOCKERC20") {}
  function mint(address account, uint256 value) external {
    _mint(account, value);
  }
}

abstract contract TestBaseContract is Test {
  address public owner = address(this);

  uint public signer_key = 0x91;
  address public signer = vm.addr(signer_key);

  uint public account1_key = 0x1234;
  address public account1 = vm.addr(account1_key);

  uint public account2_key = 0x12345;
  address public account2 = vm.addr(account2_key);

  address public diamond;
  MockERC20 public govToken;
  MockERC20 public usdcToken;

  function setUp() public virtual {
    vm.label(signer, "Default signer");
    vm.label(owner, "Owner");
    vm.label(account1, "Account 1");
    vm.label(account2, "Account 2");

    DiamondCutFacet diamondCutFacet = new DiamondCutFacet();
    diamond = address(new Diamond(owner, address(diamondCutFacet)));

    GatewayFacet gatewayFacet = new GatewayFacet();
    SigningFacet signingFacet = new SigningFacet();
    ConfigFacet configFacet = new ConfigFacet();

    IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](3);

    bytes4[] memory gatewaySelectors = new bytes4[](3);
    gatewaySelectors[0] = GatewayFacet.gatewayPoolBalance.selector;
    gatewaySelectors[1] = GatewayFacet.deposit.selector;
    gatewaySelectors[2] = GatewayFacet.withdraw.selector;
    cuts[0] = IDiamondCut.FacetCut({
      facetAddress: address(gatewayFacet),
      action: IDiamondCut.FacetCutAction.Add,
      functionSelectors: gatewaySelectors
    });

    bytes4[] memory signingSelectors = new bytes4[](1);
    signingSelectors[0] = SigningFacet.generateSignaturePayload.selector;
    cuts[1] = IDiamondCut.FacetCut({
      facetAddress: address(signingFacet),
      action: IDiamondCut.FacetCutAction.Add,
      functionSelectors: signingSelectors
    });

    bytes4[] memory configSelectors = new bytes4[](5);
    configSelectors[0] = ConfigFacet.signer.selector;
    configSelectors[1] = ConfigFacet.setSigner.selector;
    configSelectors[2] = ConfigFacet.govToken.selector;
    configSelectors[3] = ConfigFacet.setGovToken.selector;
    configSelectors[4] = ConfigFacet.usdcToken.selector;
    cuts[2] = IDiamondCut.FacetCut({
      facetAddress: address(configFacet),
      action: IDiamondCut.FacetCutAction.Add,
      functionSelectors: configSelectors
    });

    govToken = new MockERC20();
    usdcToken = new MockERC20();

    MockWETH weth = new MockWETH();

    InitDiamond init = new InitDiamond();
    IDiamondCut(diamond).diamondCut(cuts, address(init), abi.encodeWithSelector(init.init.selector, address(govToken), address(usdcToken), signer));
  }

  function _computeDefaultSig(bytes memory _data, uint _deadline) internal view returns (AuthSignature memory) {
    return _computeSig(signer_key, _data, _deadline);
  }

  function _computeSig(uint _key, bytes memory _data, uint _deadline) internal view returns (AuthSignature memory) {
    bytes32 sigHash = ECDSA.toEthSignedMessageHash(
      keccak256(LibAuth.generateSignaturePayload(_data, _deadline))
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(_key, sigHash);
    return AuthSignature({
      signature: abi.encodePacked(r, s, v),
      deadline: _deadline
    });
  }

  function _getCurrentDay() internal view returns (uint256) {
    return block.timestamp / 1 days;
  }
}
