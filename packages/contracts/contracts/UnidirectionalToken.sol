pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ECRecovery.sol";
import "openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol";

/// @title Unidirectional payment channels contract for ERC20 tokens.
contract UnidirectionalToken {
    using SafeMath for uint256;

    struct PaymentChannel {
        address sender;
        address receiver;
        uint256 value; // Total amount of money deposited to the channel.

        uint256 settlingPeriod; // How many blocks to wait for the receiver to claim her funds, after sender starts settling.
        uint256 settlingUntil; // Starting with this block number, anyone can settle the channel.
        address tokenContract;
    }

    mapping (bytes32 => PaymentChannel) public channels;

    event DidOpen(bytes32 indexed channelId, address indexed sender, address indexed receiver, uint256 value, address tokenContract);
    event DidDeposit(bytes32 indexed channelId, uint256 deposit);
    event DidClaim(bytes32 indexed channelId);
    event DidStartSettling(bytes32 indexed channelId);
    event DidSettle(bytes32 indexed channelId);

    function open(bytes32 channelId, address receiver, uint256 settlingPeriod, address tokenContract, uint256 value) public {
        require(isAbsent(channelId));

        StandardToken token = StandardToken(tokenContract);
        require(token.transferFrom(msg.sender, address(this), value));

        channels[channelId] = PaymentChannel({
            sender: msg.sender,
            receiver: receiver,
            value: value,
            settlingPeriod: settlingPeriod,
            settlingUntil: 0,
            tokenContract: tokenContract
        });

        emit DidOpen(channelId, msg.sender, receiver, value, tokenContract);
    }

    /// @notice Ensure `origin` address can claim `payment` amount on channel identified by `channelId`.
    /// @dev Check if `signature` is made by sender part of the channel, and is for payment promise (see `paymentDigest`).
    /// @param channelId Identifier of the channel.
    /// @param payment Amount claimed.
    /// @param origin Caller of `claim` function.
    /// @param signature Signature for the payment promise.
    function canClaim(bytes32 channelId, uint256 payment, address origin, bytes signature) public view returns(bool) {
        PaymentChannel storage channel = channels[channelId];
        bool isReceiver = origin == channel.receiver;
        bytes32 hash = recoveryPaymentDigest(channelId, payment, channel.tokenContract);
        bool isSigned = channel.sender == ECRecovery.recover(hash, signature);

        return isReceiver && isSigned;
    }

    /// @notice Claim the funds, and close the channel.
    /// @dev Can be claimed by channel receiver only. Guarded by `canClaim`.
    /// @param channelId Identifier of the channel.
    /// @param payment Amount claimed.
    /// @param signature Signature for the payment promise.
    function claim(bytes32 channelId, uint256 payment, bytes signature) public {
        require(canClaim(channelId, payment, msg.sender, signature));

        PaymentChannel storage channel = channels[channelId];
        StandardToken token = StandardToken(channel.tokenContract);

        if (payment >= channel.value) {
            require(token.transfer(channel.receiver, channel.value));
        } else {
            require(token.transfer(channel.receiver, payment));
            uint256 change = channel.value.sub(payment);
            require(token.transfer(channel.sender, change));
        }

        delete channels[channelId];

        emit DidClaim(channelId);
    }

    /// @notice Check if the channel is not present.
    /// @param channelId Identifier of the channel.
    function isAbsent(bytes32 channelId) public view returns(bool) {
        PaymentChannel storage channel = channels[channelId];
        return channel.sender == 0;
    }

    /// @notice Check if the channel is present: in open or settling state.
    /// @param channelId Identifier of the channel.
    function isPresent(bytes32 channelId) public view returns(bool) {
        return !isAbsent(channelId);
    }

    /// @notice Check if the channel is in settling state: waits till the settling period is over.
    /// @dev It is settling, if `settlingUntil` is set to non-zero.
    /// @param channelId Identifier of the channel.
    function isSettling(bytes32 channelId) public view returns(bool) {
        PaymentChannel storage channel = channels[channelId];
        return channel.settlingUntil != 0;
    }

    /// @notice Check if the channel is open: present and not settling.
    /// @param channelId Identifier of the channel.
    function isOpen(bytes32 channelId) public view returns(bool) {
        return isPresent(channelId) && !isSettling(channelId);
    }

    /*** PAYMENT DIGEST ***/

    /// @return Hash of the payment promise to sign.
    /// @param channelId Identifier of the channel.
    /// @param payment Amount to send, and to claim later.
    /// @param tokenContract Address of ERC20 token contract.
    function paymentDigest(bytes32 channelId, uint256 payment, address tokenContract) public view returns(bytes32) {
        return keccak256(abi.encodePacked(address(this), channelId, payment, tokenContract));
    }

    /// @return Actually signed hash of the payment promise, considering "Ethereum Signed Message" prefix.
    /// @param channelId Identifier of the channel.
    /// @param payment Amount to send, and to claim later.
    function recoveryPaymentDigest(bytes32 channelId, uint256 payment, address tokenContract) internal view returns(bytes32) {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        return keccak256(abi.encodePacked(prefix, paymentDigest(channelId, payment, tokenContract)));
    }
}