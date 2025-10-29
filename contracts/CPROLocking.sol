// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title CPRO locking contract
contract CPROLocking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    /// @notice Global unlock timestamp
    uint256 public immutable endTime;

    /// @notice Fixed amount each beneficiary receives
    uint256 public immutable sharePerBeneficiary;

    /// @notice Where leftover (unassigned) tokens go after endTime
    address public immutable sweepRecipient;

    /// @dev Total tokens allocated to beneficiaries
    uint256 public totalAssigned;

    /// @notice Total tokens claimed by beneficiaries
    uint256 public totalClaimed;

    /// @notice Number of unique beneficiaries added
    uint256 public beneficiariesCount;

    /// @dev Beneficiary address => allocated amount (0 if not beneficiary)
    mapping(address => uint256) public allocation;

    /// @dev Beneficiary address => lockId (0 if not beneficiary)
    mapping(address => uint256) public beneficiaryLockId;

    /// @dev LockId => beneficiary address
    mapping(uint256 => address) public lockOwner;

    /// @dev LockId => lock type identifier (0=team, 1=liquidity, 2=marketing, etc.)
    mapping(uint256 => uint8) public lockType;

    /// @dev Counter for unique lock IDs
    uint256 private nextLockId = 1;

    event Funded(address indexed from, uint256 amount);
    event BeneficiaryAdded(
        address indexed beneficiary,
        uint256 indexed lockId,
        uint256 amount,
        uint8 lockType,
        uint256 unlockTime
    );
    event Claimed(
        address indexed beneficiary,
        uint256 indexed lockId,
        uint256 amount
    );
    event Swept(address indexed to, uint256 amount);

    error PastDeadline();
    error BeforeDeadline();
    error AlreadyBeneficiary();
    error NothingToClaim();
    error NotEnoughFunded();
    error NoSweepable();
    error InvalidLockType();

    constructor(
        address token_,
        uint256 poolSize_,
        uint256 numBeneficiaries_,
        address sweepRecipient_
    ) Ownable(msg.sender) {
        require(token_ != address(0), "CPROLocking: token is zero address");
        require(
            sweepRecipient_ != address(0),
            "CPROLocking: no sweep recipient found provided"
        );
        require(poolSize_ > 0, "CPROLocking: pool size must be greater than 0");
        require(
            numBeneficiaries_ > 0,
            "CPROLocking: expected beneficiaries count must be greater than 0"
        );

        token = IERC20(token_);
        endTime = block.timestamp + 365 days; //Setting the fixed unlock date to one year in the future after deployment
        sweepRecipient = sweepRecipient_;

        sharePerBeneficiary = poolSize_ / numBeneficiaries_;
        require(
            sharePerBeneficiary > 0,
            "CPROLocking: per-beneficiary share must greater than 0"
        );
    }

    /// @notice Transfer tokens from owner into this contract.
    function fund(uint256 amount) external onlyOwner {
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Funded(msg.sender, amount);
    }

    /// @notice Add a new beneficiary. Can be added only before the deadline.
    /// @param beneficiary Address to receive tokens
    /// @param lockType_ Type identifier (0-25)
    function addBeneficiary(
        address beneficiary,
        uint8 lockType_
    ) external onlyOwner {
        if (block.timestamp >= endTime) revert PastDeadline();
        require(
            beneficiary != address(0),
            "CPROLocking: beneficiary is zero address"
        );
        if (allocation[beneficiary] != 0) revert AlreadyBeneficiary();
        if (lockType_ > 25) revert InvalidLockType(); //should be the number of locking contracts

        // Ensure funding covers all assigned shares (including this one)
        if (
            token.balanceOf(address(this)) < totalAssigned + sharePerBeneficiary
        ) revert NotEnoughFunded();

        uint256 lockId = nextLockId++;

        allocation[beneficiary] = sharePerBeneficiary;
        beneficiaryLockId[beneficiary] = lockId;
        lockOwner[lockId] = beneficiary;
        lockType[lockId] = lockType_;
        totalAssigned += sharePerBeneficiary;
        beneficiariesCount += 1;

        emit BeneficiaryAdded(
            beneficiary,
            lockId,
            sharePerBeneficiary,
            lockType_,
            endTime
        );
    }

    /// @notice Check if you can claim your tokens after the deadline has ended.
    function canClaim(address user) external view returns (bool) {
        return block.timestamp >= endTime && allocation[user] != 0;
    }

    /// @notice Claim your tokens after the fixed global unlock time.
    function claim() external nonReentrant {
        if (block.timestamp < endTime) revert BeforeDeadline();

        uint256 amount = allocation[msg.sender];
        if (amount == 0) revert NothingToClaim();

        uint256 lockId = beneficiaryLockId[msg.sender];

        allocation[msg.sender] = 0;
        totalClaimed += amount;

        token.safeTransfer(msg.sender, amount);
        emit Claimed(msg.sender, lockId, amount);
    }

    /// @notice Get lock information for a beneficiary
    /// @param beneficiary Address to query
    /// @return lockId Unique lock identifier
    /// @return amount Tokens locked
    /// @return unlockTime When tokens unlock
    /// @return claimed Whether tokens were claimed
    /// @return lockTypeId Type of lock
    function getBeneficiaryLockInfo(
        address beneficiary
    )
        external
        view
        returns (
            uint256 lockId,
            uint256 amount,
            uint256 unlockTime,
            bool claimed,
            uint8 lockTypeId
        )
    {
        lockId = beneficiaryLockId[beneficiary];
        if (lockId == 0) {
            return (0, 0, 0, false, 0);
        }

        amount = sharePerBeneficiary;
        unlockTime = endTime;
        claimed = (allocation[beneficiary] == 0 &&
            lockOwner[lockId] != address(0));
        lockTypeId = lockType[lockId];
    }

    /// @notice Get lock information by lock ID
    /// @param lockId Lock identifier
    /// @return owner Beneficiary address
    /// @return amount Tokens locked
    /// @return unlockTime When tokens unlock
    /// @return claimed Whether tokens were claimed
    /// @return lockTypeId Type of lock
    function getLockInfo(
        uint256 lockId
    )
        external
        view
        returns (
            address owner,
            uint256 amount,
            uint256 unlockTime,
            bool claimed,
            uint8 lockTypeId
        )
    {
        owner = lockOwner[lockId];
        //It should not be zero address, but we check all the same
        if (owner == address(0)) {
            return (address(0), 0, 0, false, 0);
        }
        amount = sharePerBeneficiary;
        unlockTime = endTime;
        claimed = (allocation[owner] == 0);
        lockTypeId = lockType[lockId];
    }

    /// @notice Amount that must remain in the contract to satisfy all unclaimed allocations.
    function reservedForUnclaimed() public view returns (uint256) {
        return totalAssigned - totalClaimed;
    }

    function sweepUnassigned() external onlyOwner {
        if (block.timestamp < endTime) revert BeforeDeadline();

        uint256 balance = token.balanceOf(address(this));
        uint256 reserved = reservedForUnclaimed();
        require(balance >= reserved, "CPROLocking: invariant violated");

        uint256 sweepable = balance - reserved;
        if (sweepable == 0) revert NoSweepable();

        token.safeTransfer(sweepRecipient, sweepable);
        emit Swept(sweepRecipient, sweepable);
    }
}
