// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title CPROToken
 * @notice ERC20 token with transfer fees, voting capabilities, and administrative controls
 * @dev This contract extends OpenZeppelin's ERC20 with:
 *      - Transfer fees: Configurable fee percentage (max 5%) deducted from transfers
 *      - Voting: ERC20Votes for governance participation
 *      - Pausable: Emergency pause functionality
 *      - Capped: Maximum supply limit
 *      - Burnable: Token burning capability
 *      - Permit: Gasless approvals via EIP-2612
 * 
 * Transfer Fee Mechanism:
 * - Fees are only charged on transfers (not on minting or burning)
 * - Fees are deducted from the transfer amount
 * - Fee recipient receives the fee amount if set
 * - If fee recipient is not set (address(0)), fees are explicitly burned (decreases total supply)
 * - Voting power checkpoints are properly maintained for all parties
 * - Fees can be enabled/disabled by the owner
 * - Burns are excluded from fees to ensure deterministic burn behavior
 * - Fee exemptions: Certain addresses (DEX pairs, bridges, staking contracts) can be exempted
 *   from fees to improve DeFi protocol compatibility
 */
contract CPROToken is
    ERC20,
    Ownable,
    ERC20Burnable,
    ERC20Capped,
    ERC20Pausable,
    ERC20Votes,
    ERC20Permit
{
    /// @notice Maximum token supply (1 billion tokens)
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;
    
    /// @notice Maximum transfer fee allowed (500 basis points = 5%)
    uint256 public constant MAX_FEE_BASIS_POINTS = 500;

    /// @notice Transfer fee percentage in basis points (10000 = 100%, 100 = 1%)
    uint256 public transferFeeBasisPoints;
    
    /// @notice Address that receives transfer fees
    address public feeRecipient;
    
    /// @notice Whether transfer fees are currently enabled
    bool public transferFeeEnabled;

    /// @notice Mapping of addresses exempt from transfer fees
    /// @dev Common exemptions: DEX pairs, bridges, treasury, staking contracts
    mapping(address => bool) public isFeeExempt;

    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurnedByOwner(uint256 amount);
    event TokensRecovered(address indexed tokenAddress, uint256 amount);
    event TransferFeeUpdated(uint256 oldBasisPoints, uint256 newBasisPoints);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event TransferFeeToggled(bool enabled);
    event FeeExemptionUpdated(address indexed account, bool exempt);

    constructor()
        ERC20("CPROToken", "CPRO")
        ERC20Capped(MAX_SUPPLY)
        Ownable(msg.sender)
        ERC20Permit("CPROToken")
    {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }

    /**
     * Mint new tokens. Only contract owner can mint new tokens when not in paused state.
     * @param to Receiver address of the new tokens
     * @param amount amount of tokens to mint in wei
     */
    function mint(address to, uint256 amount) external onlyOwner whenNotPaused {
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    /**
     * Burns a set amount of tokens by sending them to a burn address removing a set amount of tokens from supply. Effect similar to that of public trading company buying back its stock.
     * @param amount amount of tokens to burn from the owners balance
     */
    function burnFromOwner(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
        emit TokensBurnedByOwner(amount);
    }

    /**
     * Emergency pause functionality for stop all transfers
     */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function recoverERC20(
        address tokenAddress,
        uint256 tokenAmount
    ) external onlyOwner {
        require(
            tokenAddress != address(this),
            "CPROToken: Cannot recover own tokens"
        );
        require(tokenAddress != address(0), "CPROToken: Invalid token address");
        require(tokenAmount > 0, "CPROToken: Amount must be greater than 0");
        SafeERC20.safeTransfer(IERC20(tokenAddress), owner(), tokenAmount);
        emit TokensRecovered(tokenAddress, tokenAmount);
    }

    /**
     * @notice Set the transfer fee in basis points (10000 = 100%)
     * @param basisPoints Fee percentage in basis points (max 500 = 5%)
     */
    function setTransferFee(uint256 basisPoints) external onlyOwner {
        require(
            basisPoints <= MAX_FEE_BASIS_POINTS,
            "CPROToken: Fee too high"
        );
        uint256 oldFee = transferFeeBasisPoints;
        transferFeeBasisPoints = basisPoints;
        emit TransferFeeUpdated(oldFee, basisPoints);
    }

    /**
     * @notice Set the address that receives transfer fees
     * @param recipient Address to receive fees
     */
    function setFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "CPROToken: Invalid recipient");
        require(
            recipient != address(this),
            "CPROToken: Cannot use contract as recipient"
        );
        address oldRecipient = feeRecipient;
        feeRecipient = recipient;
        emit FeeRecipientUpdated(oldRecipient, recipient);
    }

    /**
     * @notice Enable or disable transfer fees
     * @param enabled True to enable fees, false to disable
     */
    function setTransferFeeEnabled(bool enabled) external onlyOwner {
        bool oldEnabled = transferFeeEnabled;
        transferFeeEnabled = enabled;
        emit TransferFeeToggled(enabled);
    }

    /**
     * @notice Set fee exemption status for an address
     * @dev Used to exempt addresses from transfer fees for DeFi compatibility.
     *      Common exemptions: DEX pairs, bridges, treasury, staking contracts.
     *      Exemptions apply to both sender and receiver - if either is exempt, no fee is charged.
     * @param account Address to set exemption status for
     * @param exempt True to exempt from fees, false to apply fees
     */
    function setFeeExemption(address account, bool exempt) external onlyOwner {
        require(account != address(0), "CPROToken: Invalid account");
        bool oldExempt = isFeeExempt[account];
        isFeeExempt[account] = exempt;
        emit FeeExemptionUpdated(account, exempt);
    }

    /**
     * @notice Batch set fee exemption status for multiple addresses
     * @dev Gas-efficient way to set exemptions for multiple addresses at once
     * @param accounts Array of addresses to set exemption status for
     * @param exempts Array of exemption statuses (true = exempt, false = not exempt)
     */
    function batchSetFeeExemptions(
        address[] calldata accounts,
        bool[] calldata exempts
    ) external onlyOwner {
        require(
            accounts.length == exempts.length,
            "CPROToken: Arrays length mismatch"
        );
        require(accounts.length > 0, "CPROToken: Empty arrays");

        for (uint256 i = 0; i < accounts.length; i++) {
            require(accounts[i] != address(0), "CPROToken: Invalid account");
            isFeeExempt[accounts[i]] = exempts[i];
            emit FeeExemptionUpdated(accounts[i], exempts[i]);
        }
    }

    /**
     * @notice Override _update to implement transfer fee logic
     * @dev Calculates and deducts fee from transfers, maintaining voting power checkpoints.
     *      Fees are NOT applied to:
     *      - Minting (from == address(0))
     *      - Burning (to == address(0))
     *      - Transfers from or to exempt addresses (isFeeExempt[from] or isFeeExempt[to])
     *      Fees are only applied to regular transfers between non-zero, non-exempt addresses.
     *      If feeRecipient is set, fee is sent to recipient. If feeRecipient is address(0),
     *      fee is explicitly burned (decreases total supply via transfer to address(0)).
     *      Voting power checkpoints are updated for sender, receiver, and fee recipient (or burn).
     * @param from Address tokens are transferred from
     * @param to Address tokens are transferred to
     * @param amount Amount of tokens to transfer
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Capped, ERC20Pausable, ERC20Votes) {
        // Apply transfer fee if enabled, not minting, not burning, not exempt, and amount > 0
        // Cache state variables to save gas (SLOAD operations)
        bool feeEnabled = transferFeeEnabled;
        if (
            feeEnabled &&
            from != address(0) &&
            to != address(0) &&
            amount > 0 &&
            !isFeeExempt[from] &&
            !isFeeExempt[to]
        ) {
            uint256 feeBasisPoints = transferFeeBasisPoints;
            // Calculate fee using checked arithmetic (Solidity 0.8+ prevents overflow)
            uint256 fee = (amount * feeBasisPoints) / 10000;
            uint256 transferAmount = amount - fee;

            // Update main transfer (from → to) - updates voting power checkpoints
            super._update(from, to, transferAmount);

            // Handle fee: either send to recipient or burn if recipient is not set
            // Cache feeRecipient to save gas
            address recipient = feeRecipient;
            if (fee > 0) {
                if (recipient != address(0)) {
                    // Send fee to recipient - updates voting power checkpoints
                    super._update(from, recipient, fee);
                } else {
                    // Explicitly burn the fee - decreases total supply and updates voting power
                    super._update(from, address(0), fee);
                }
            }
        } else {
            // No fee, normal transfer
            super._update(from, to, amount);
        }
    }

    function nonces(
        address owner
    ) public view virtual override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
