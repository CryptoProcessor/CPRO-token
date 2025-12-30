// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {CPROToken} from "../src/CPROToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Mock ERC20 token for testing recovery functionality
contract MockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

contract CPROTokenTest is Test {
    CPROToken public token;
    MockERC20 public mockToken;

    address public owner;
    address public user1;
    address public user2;
    address public nonOwner;

    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 public constant INITIAL_SUPPLY = 1000000 * 10 ** 18;

    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurnedByOwner(uint256 amount);
    event TokensRecovered(address indexed tokenAddress, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        nonOwner = makeAddr("nonOwner");

        token = new CPROToken();
        mockToken = new MockERC20();
    }

    // Constructor
    function testConstructor() public view {
        assertEq(token.name(), "CPROToken");
        assertEq(token.symbol(), "CPRO");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
        assertEq(token.owner(), owner);
        assertEq(token.cap(), MAX_SUPPLY);
        assertFalse(token.paused());
    }

    // Minting
    function testMint() public {
        uint256 mintAmount = 1000 * 10 ** 18;
        uint256 initialSupply = token.totalSupply();
        uint256 initialBalance = token.balanceOf(user1);

        vm.expectEmit(true, false, false, true);
        emit TokensMinted(user1, mintAmount);

        token.mint(user1, mintAmount);

        assertEq(token.totalSupply(), initialSupply + mintAmount);
        assertEq(token.balanceOf(user1), initialBalance + mintAmount);
    }

    function testMintOnlyOwner() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        token.mint(user1, mintAmount);
    }

    function testMintCapExceeded() public {
        uint256 remainingSupply = MAX_SUPPLY - token.totalSupply();
        uint256 excessAmount = remainingSupply + 1;

        vm.expectRevert("CPROToken: Cap exceeded");
        token.mint(user1, excessAmount);
    }

    function testMintExactlyCap() public {
        uint256 remainingSupply = MAX_SUPPLY - token.totalSupply();

        token.mint(user1, remainingSupply);

        assertEq(token.totalSupply(), MAX_SUPPLY);
        assertEq(token.balanceOf(user1), remainingSupply);
    }

    // Burning
    function testBurnFromOwner() public {
        uint256 burnAmount = 100 * 10 ** 18;
        uint256 initialSupply = token.totalSupply();
        uint256 initialBalance = token.balanceOf(owner);

        vm.expectEmit(true, false, false, true);
        emit TokensBurnedByOwner(burnAmount);

        token.burnFromOwner(burnAmount);

        assertEq(token.totalSupply(), initialSupply - burnAmount);
        assertEq(token.balanceOf(owner), initialBalance - burnAmount);
    }

    function testBurnFromOwnerOnlyOwner() public {
        uint256 burnAmount = 100 * 10 ** 18;

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        token.burnFromOwner(burnAmount);
    }

    function testBurnFromOwnerInsufficientBalance() public {
        uint256 burnAmount = token.balanceOf(owner) + 1;

        vm.expectRevert();
        token.burnFromOwner(burnAmount);
    }

    // ERC20Burnable
    function testBurn() public {
        uint256 burnAmount = 100 * 10 ** 18;
        uint256 initialSupply = token.totalSupply();
        uint256 initialBalance = token.balanceOf(owner);

        token.burn(burnAmount);

        assertEq(token.totalSupply(), initialSupply - burnAmount);
        assertEq(token.balanceOf(owner), initialBalance - burnAmount);
    }

    function testBurnFrom() public {
        uint256 burnAmount = 100 * 10 ** 18;

        // Give user1 some tokens
        token.mint(user1, burnAmount * 2);

        // User1 approves owner to burn tokens
        vm.prank(user1);
        token.approve(owner, burnAmount);

        uint256 initialSupply = token.totalSupply();
        uint256 initialBalance = token.balanceOf(user1);

        token.burnFrom(user1, burnAmount);

        assertEq(token.totalSupply(), initialSupply - burnAmount);
        assertEq(token.balanceOf(user1), initialBalance - burnAmount);
        assertEq(token.allowance(user1, owner), 0);
    }

    // Pause/Unpause
    function testPause() public {
        vm.expectEmit(true, false, false, false);
        emit Paused(owner);

        token.pause();

        assertTrue(token.paused());
    }

    function testUnpause() public {
        token.pause();
        assertTrue(token.paused());

        vm.expectEmit(true, false, false, false);
        emit Unpaused(owner);

        token.unpause();

        assertFalse(token.paused());
    }

    function testPauseOnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        token.pause();
    }

    function testUnpauseOnlyOwner() public {
        token.pause();

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        token.unpause();
    }

    function testTransferWhenPaused() public {
        token.mint(user1, 1000 * 10 ** 18);
        token.pause();

        vm.prank(user1);
        vm.expectRevert();
        token.transfer(user2, 100 * 10 ** 18);
    }

    function testMintWhenPaused() public {
        token.pause();

        vm.expectRevert();
        token.mint(user1, 1000 * 10 ** 18);
    }

    // Recovery
    function testRecoverERC20() public {
        uint256 recoveryAmount = 1000 * 10 ** 18;

        // Send mock tokens to the CPRO contract
        mockToken.transfer(address(token), recoveryAmount);
        assertEq(mockToken.balanceOf(address(token)), recoveryAmount);

        uint256 initialOwnerBalance = mockToken.balanceOf(owner);

        vm.expectEmit(true, false, false, true);
        emit TokensRecovered(address(mockToken), recoveryAmount);

        token.recoverERC20(address(mockToken), recoveryAmount);

        assertEq(mockToken.balanceOf(address(token)), 0);
        assertEq(
            mockToken.balanceOf(owner),
            initialOwnerBalance + recoveryAmount
        );
    }

    function testRecoverERC20OnlyOwner() public {
        uint256 recoveryAmount = 1000 * 10 ** 18;

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        token.recoverERC20(address(mockToken), recoveryAmount);
    }

    function testRecoverERC20CannotRecoverOwnTokens() public {
        uint256 recoveryAmount = 1000 * 10 ** 18;

        vm.expectRevert("CPROToken: Cannot recover own tokens");
        token.recoverERC20(address(token), recoveryAmount);
    }

    function testRecoverERC20InvalidTokenAddress() public {
        uint256 recoveryAmount = 1000 * 10 ** 18;

        vm.expectRevert("CPROToken: Invalid token address");
        token.recoverERC20(address(0), recoveryAmount);
    }

    function testRecoverERC20ZeroAmount() public {
        vm.expectRevert("CPROToken: Amount must be greater than 0");
        token.recoverERC20(address(mockToken), 0);
    }

    // Transfer Tests
    function testTransfer() public {
        uint256 transferAmount = 1000 * 10 ** 18;

        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, user1, transferAmount);

        token.transfer(user1, transferAmount);

        assertEq(token.balanceOf(user1), transferAmount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - transferAmount);
    }

    function testTransferFrom() public {
        uint256 transferAmount = 1000 * 10 ** 18;

        // Approve user1 to spend owner's tokens
        token.approve(user1, transferAmount);

        vm.prank(user1);
        token.transferFrom(owner, user2, transferAmount);

        assertEq(token.balanceOf(user2), transferAmount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - transferAmount);
        assertEq(token.allowance(owner, user1), 0);
    }

    // Edge Cases and Fuzz Tests
    function testFuzzMint(uint256 amount) public {
        amount = bound(amount, 1, MAX_SUPPLY - token.totalSupply());

        uint256 initialSupply = token.totalSupply();
        token.mint(user1, amount);

        assertEq(token.totalSupply(), initialSupply + amount);
        assertEq(token.balanceOf(user1), amount);
    }

    function testFuzzBurnFromOwner(uint256 amount) public {
        amount = bound(amount, 1, token.balanceOf(owner));

        uint256 initialSupply = token.totalSupply();
        uint256 initialBalance = token.balanceOf(owner);

        token.burnFromOwner(amount);

        assertEq(token.totalSupply(), initialSupply - amount);
        assertEq(token.balanceOf(owner), initialBalance - amount);
    }

    function testMultipleMintAndBurn() public {
        uint256 mintAmount1 = 1000 * 10 ** 18;
        uint256 mintAmount2 = 2000 * 10 ** 18;
        uint256 burnAmount = 500 * 10 ** 18;

        uint256 initialSupply = token.totalSupply();

        // Multiple mints
        token.mint(user1, mintAmount1);
        token.mint(user2, mintAmount2);

        // Burn from owner
        token.burnFromOwner(burnAmount);

        uint256 expectedSupply = initialSupply +
            mintAmount1 +
            mintAmount2 -
            burnAmount;
        assertEq(token.totalSupply(), expectedSupply);
        assertEq(token.balanceOf(user1), mintAmount1);
        assertEq(token.balanceOf(user2), mintAmount2);
    }

    // Gas optimization tests
    function testGasMint() public {
        uint256 gasStart = gasleft();
        token.mint(user1, 1000 * 10 ** 18);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for mint:", gasUsed);
        assertTrue(gasUsed > 0); // Simple assertion to make it a proper test
    }
}
