// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/IDLN.sol";
import "./interfaces/IERC6551Registry.sol";
import {Pausable} from "@openzeppelin/contracts@5.0.2/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts@5.0.2/interfaces/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts@5.0.2/access/AccessControl.sol";

contract deBridgeM3terPayment is Pausable, AccessControl {
    bytes32 public constant PAUSER = keccak256("PAUSER");

    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // ToDo: USDC token address
    address public constant TBA_IMPLEMENTATION = 0xf52d861E8d057bF7685e5C9462571dFf236249cF; // ToDo: add actual M3terPayableTBA
    address public constant DLN_SOURCE_ADDRESS = 0xeF4fB24aD0916217251F553c0596F8Edc630EB66;
    address public constant TBA_REGISTRY = 0x000000006551c19487814612e58FE06813775758;
    address public constant M3TER = 0x39fb420Bd583cCC8Afd1A1eAce2907fe300ABD02;
    uint256 public constant GNOSIS_CHAIN_ID = 100;

    error TransferError();
    error ValueError();

    event Revenue(
        uint256 indexed tokenId, uint256 indexed amount, bytes32 indexed orderId, address from, uint256 timestamp
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER, msg.sender);
    }

    function pay(uint256 giveAmount, uint256 takeAmount, uint256 tokenId)
        external
        payable
        whenNotPaused
        returns (bytes32 orderId)
    {
        // getting the protocol fee
        uint256 protocolFee = DlnSource(DLN_SOURCE_ADDRESS).globalFixedNativeFee();
        if (msg.value < protocolFee) revert ValueError();
        if (!USDC.transferFrom(msg.sender, address(this), giveAmount)) {
            revert TransferError();
        }
        address _m3terAccount = m3terAccount(tokenId);

        // preparing an order
        OrderCreation memory order = OrderCreation({
            giveTokenAddress: address(USDC),
            giveAmount: giveAmount,
            takeTokenAddress: abi.encodePacked(address(0)), // native asset (xDAI)
            takeAmount: takeAmount,
            takeChainId: GNOSIS_CHAIN_ID,
            receiverDst: abi.encodePacked(_m3terAccount),
            givePatchAuthoritySrc: _m3terAccount,
            orderAuthorityAddressDst: abi.encodePacked(_m3terAccount),
            allowedTakerDst: "",
            externalCall: "",
            allowedCancelBeneficiarySrc: ""
        });

        // giving approval
        USDC.approve(DLN_SOURCE_ADDRESS, giveAmount);

        // placing an order
        orderId = DlnSource(DLN_SOURCE_ADDRESS).createOrder{value: protocolFee}(order, "", 0, "");
        emit Revenue(tokenId, msg.value, orderId, msg.sender, block.timestamp);
    }

    function pause() public onlyRole(PAUSER) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER) {
        _unpause();
    }

    function m3terAccount(uint256 tokenId) public view returns (address) {
        return IERC6551Registry(TBA_REGISTRY).account(TBA_IMPLEMENTATION, 0x0, GNOSIS_CHAIN_ID, M3TER, tokenId);
    }
}
