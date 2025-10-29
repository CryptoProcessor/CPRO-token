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

contract CPROToken is
    ERC20,
    Ownable,
    ERC20Burnable,
    ERC20Capped,
    ERC20Pausable,
    ERC20Votes,
    ERC20Permit
{
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;

    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurnedByOwner(uint256 amount);
    event TokensRecovered(address indexed tokenAddress, uint256 amount);

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
     * Voting functionality
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Capped, ERC20Pausable, ERC20Votes) {
        super._update(from, to, amount);
    }

    function nonces(
        address owner
    ) public view virtual override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
