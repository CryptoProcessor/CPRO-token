// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract CPROVesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    struct VestingSchedule {
        uint256 totalAmount; // Total tokens to be vested
        uint256 claimedAmount; // Amount already claimed
        uint256 startTime; // When vesting starts
        uint256 cliffDuration; // Cliff period in seconds
        uint256 vestingDuration; // Total vesting duration in seconds
        bool revoked; // Whether the schedule has been revoked
        bool exists; // Whether this schedule exists
    }

    IERC20 public immutable token;

    // Beneficiary address => VestingSchedule
    mapping(address => VestingSchedule) public vestingSchedules;

    // All beneficiaries
    address[] public beneficiaries;

    // Events
    event VestingScheduleCreated(
        address indexed beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration
    );

    event TokensClaimed(address indexed beneficiary, uint256 amount);
    event VestingRevoked(address indexed beneficiary, uint256 unvestedAmount);

    constructor(address _token) Ownable(msg.sender) {
        require(_token != address(0), "CPROVesting: token is zero address");
        token = IERC20(_token);
    }

    /**
     * @dev Creates a vesting schedule for a beneficiary
     * @param beneficiary Address of the beneficiary
     * @param totalAmount Total amount of tokens to vest
     * @param startTime Timestamp vesting start
     * @param cliffDuration Duration of cliff period in seconds
     * @param vestingDuration Total vesting duration in seconds
     */
    function createVestingSchedule(
        address beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration
    ) external onlyOwner {
        require(
            beneficiary != address(0),
            "CPROVesting: beneficiary is zero address"
        );
        require(totalAmount > 0, "CPROVesting: total amount must be > 0");
        require(
            vestingDuration > 0,
            "CPROVesting: vesting duration must be > 0"
        );
        require(
            cliffDuration <= vestingDuration,
            "CPROVesting: cliff duration exceeds vesting duration"
        );
        require(
            !vestingSchedules[beneficiary].exists,
            "CPROVesting: schedule already exists for beneficiary"
        );

        // Transfer tokens to this contract for vesting
        token.safeTransferFrom(msg.sender, address(this), totalAmount);

        vestingSchedules[beneficiary] = VestingSchedule({
            totalAmount: totalAmount,
            claimedAmount: 0,
            startTime: startTime,
            cliffDuration: cliffDuration,
            vestingDuration: vestingDuration,
            revoked: false,
            exists: true
        });

        beneficiaries.push(beneficiary);

        emit VestingScheduleCreated(
            beneficiary,
            totalAmount,
            startTime,
            cliffDuration,
            vestingDuration
        );
    }

    /**
     * @dev Calculates the amount of tokens that can be claimed by a beneficiary
     * @param beneficiary Address to check
     * @return claimableAmount Amount of tokens that can be claimed
     */
    function getClaimableAmount(
        address beneficiary
    ) public view returns (uint256) {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];

        if (!schedule.exists || schedule.revoked) {
            return 0;
        }

        uint256 vested = _calculateVestedAmount(schedule);
        if (vested <= schedule.claimedAmount) return 0;
        return vested - schedule.claimedAmount;
    }

    /**
     * @dev Calculates total vested amount for a beneficiary at current time
     * @param beneficiary Address to check
     * @return vestedAmount Total amount vested so far
     */
    function getVestedAmount(
        address beneficiary
    ) public view returns (uint256) {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];

        if (!schedule.exists || schedule.revoked) {
            return 0;
        }

        return _calculateVestedAmount(schedule);
    }

    /**
     * @dev Internal function to calculate vested amount based on time
     */
    function _calculateVestedAmount(
        VestingSchedule storage schedule
    ) internal view returns (uint256) {
        if (block.timestamp < schedule.startTime + schedule.cliffDuration) {
            // in cliff
            return 0;
        }

        if (block.timestamp >= schedule.startTime + schedule.vestingDuration) {
            // Vesting done
            return schedule.totalAmount;
        }

        // Linear vesting after cliff
        uint256 timeFromStart = block.timestamp - schedule.startTime;
        return
            (schedule.totalAmount * timeFromStart) / schedule.vestingDuration;
    }

    /**
     * Only valid CPRO - ERC20 will have no transfer or burn fees.
     * @dev Allows beneficiary to claim vested tokens
     */
    function claimTokens() external nonReentrant {
        address beneficiary = msg.sender;
        uint256 claimableAmount = getClaimableAmount(beneficiary);

        require(claimableAmount > 0, "CPROVesting: no tokens to claim");

        vestingSchedules[beneficiary].claimedAmount += claimableAmount;

        token.safeTransfer(beneficiary, claimableAmount);

        emit TokensClaimed(beneficiary, claimableAmount);
    }

    /**
     * @dev Owner can revoke vesting schedule (returns unvested tokens)
     * @param beneficiary Address whose vesting to revoke
     */
    function revokeVesting(
        address beneficiary
    ) external onlyOwner nonReentrant {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];

        require(schedule.exists, "CPROVesting: no vesting schedule exists");
        require(!schedule.revoked, "CPROVesting: already revoked");

        uint256 vestedAmount = _calculateVestedAmount(schedule);
        uint256 dueToBeneficiary = vestedAmount > schedule.claimedAmount
            ? (vestedAmount - schedule.claimedAmount)
            : 0;
        uint256 unvestedAmount = schedule.totalAmount - vestedAmount;

        schedule.claimedAmount += dueToBeneficiary;
        schedule.revoked = true;
        schedule.exists = false; //if left true we cannot create a new schedule for the same beneficiary

        //Transfer due tokens to beneficiaries
        if (dueToBeneficiary > 0) {
            token.safeTransfer(beneficiary, dueToBeneficiary);
            emit TokensClaimed(beneficiary, dueToBeneficiary);
        }

        // Return unvested tokens to owner
        if (unvestedAmount > 0) {
            token.safeTransfer(owner(), unvestedAmount);
        }

        emit VestingRevoked(beneficiary, unvestedAmount);
    }

    /**
     * @dev Get vesting schedule details for a beneficiary
     */
    function getBeneficiaryVestingSchedule(
        address beneficiary
    )
        external
        view
        returns (
            uint256 totalAmount,
            uint256 claimedAmount,
            uint256 startTime,
            uint256 cliffDuration,
            uint256 vestingDuration,
            bool revoked
        )
    {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        return (
            schedule.totalAmount,
            schedule.claimedAmount,
            schedule.startTime,
            schedule.cliffDuration,
            schedule.vestingDuration,
            schedule.revoked
        );
    }

    /**
     * @dev Get total number of beneficiaries
     */
    function getBeneficiariesCount() external view returns (uint256) {
        return beneficiaries.length;
    }

    /**
     * @dev Get beneficiary address by index
     */
    function getBeneficiary(uint256 index) external view returns (address) {
        require(
            index < beneficiaries.length,
            "CPROVesting: index out of bounds"
        );
        return beneficiaries[index];
    }

    /**
     * @dev Emergency function to withdraw any ERC20 tokens sent by mistake
     * Only works for tokens other than the vesting token
     */
    function emergencyWithdraw(
        address _token,
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(
            _token != address(token),
            "CPROVesting: cannot withdraw vesting token"
        );
        IERC20(_token).safeTransfer(owner(), amount);
    }
}
