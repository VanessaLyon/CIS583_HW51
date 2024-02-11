// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AMM is AccessControl {
    using SafeERC20 for ERC20;

    bytes32 public constant LP_ROLE = keccak256("LP_ROLE");
    uint256 public invariant;
    address public tokenA;
    address public tokenB;
    uint256 public constant feebps = 3; // Fee in basis points

    // Store liquidity provided by each address
    mapping(address => uint256) public liquidity;

    event Swap(address indexed _inToken, address indexed _outToken, uint256 inAmt, uint256 outAmt);
    event LiquidityProvision(address indexed _from, uint256 AQty, uint256 BQty);
    event Withdrawal(address indexed _from, address indexed recipient, uint256 AQty, uint256 BQty);

    constructor(address _tokenA, address _tokenB) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(LP_ROLE, msg.sender);

        require(_tokenA != address(0) && _tokenB != address(0), 'Token address cannot be 0');
        require(_tokenA != _tokenB, 'Tokens cannot be the same');

        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function provideLiquidity(uint256 amtA, uint256 amtB) public {
        require(amtA > 0 && amtB > 0, 'Cannot provide 0 liquidity');
        
        ERC20(tokenA).safeTransferFrom(msg.sender, address(this), amtA);
        ERC20(tokenB).safeTransferFrom(msg.sender, address(this), amtB);

        
        uint256 liquidityTokens = amtA + amtB; // Simplified calculation
        liquidity[msg.sender] += liquidityTokens;

        updateInvariant();
        
        emit LiquidityProvision(msg.sender, amtA, amtB);
    }

    function withdrawLiquidity2(address recipient, uint256 amtA, uint256 amtB) public onlyRole(LP_ROLE) {
        require(amtA > 0 && amtB > 0, 'Cannot withdraw 0');
        require(recipient != address(0), 'Cannot withdraw to 0 address');

        // Ensure the caller has enough liquidity tokens - simplified model
        require(liquidity[msg.sender] >= amtA + amtB, "Insufficient liquidity");

        ERC20(tokenA).safeTransfer(recipient, amtA);
        ERC20(tokenB).safeTransfer(recipient, amtB);

        // Burn liquidity tokens - simplified model
        liquidity[msg.sender] -= (amtA + amtB);

        updateInvariant();

        emit Withdrawal(msg.sender, recipient, amtA, amtB);
    }

  function withdrawLiquidity(address recipient, uint256 amtA, uint256 amtB) public {
    // Check for non-zero withdrawal request
    require(amtA > 0 || amtB > 0, 'Cannot withdraw 0');
    require(recipient != address(0), 'Cannot withdraw to 0 address');

    // Check if the caller has the LP_ROLE
    require(hasRole(LP_ROLE, msg.sender), "Unauthorized");

    uint256 liquidityBalance = liquidity[msg.sender];
    // Checks
    require(
        (amtA == 0 || ERC20(tokenA).balanceOf(address(this)) >= amtA) &&
        (amtB == 0 || ERC20(tokenB).balanceOf(address(this)) >= amtB),
        "Insufficient liquidity"
    );

    if(amtA > 0) {
        ERC20(tokenA).safeTransfer(recipient, amtA);
    }
    if(amtB > 0) {
        ERC20(tokenB).safeTransfer(recipient, amtB);
    }

    // Update the liquidity record for the LP. 
    if (amtA > 0 && amtB > 0) {
        // Assuming a 1:1 ratio for simplicity. Adjust based on actual pool share.
        liquidity[msg.sender] -= (amtA + amtB);
    } else if (amtA > 0) {
        liquidity[msg.sender] -= amtA;
    } else if (amtB > 0) {
        liquidity[msg.sender] -= amtB;
    }

    updateInvariant();

    emit Withdrawal(msg.sender, recipient, amtA, amtB);
  }


    function tradeTokens(address sellToken, uint256 sellAmount) public {
        require(invariant > 0, 'Invariant must be nonzero');
        require(sellToken == tokenA || sellToken == tokenB, 'Invalid token');
        require(sellAmount > 0, 'Cannot trade 0');

        address buyToken = (sellToken == tokenA) ? tokenB : tokenA;
        uint256 sellTokenBalance = ERC20(sellToken).balanceOf(address(this));
        uint256 buyTokenBalance = ERC20(buyToken).balanceOf(address(this));

        // Apply fee
        uint256 feeAmount = (sellAmount * feebps) / 10000;
        uint256 adjustedAmount = sellAmount - feeAmount;

        // Calculate buy amount using the constant product formula and adjust for fee
        uint256 buyAmount = getBuyAmount(sellToken, buyToken, adjustedAmount, sellTokenBalance, buyTokenBalance);

        require(buyAmount > 0 && buyAmount <= ERC20(buyToken).balanceOf(address(this)), 'Invalid trade');

        ERC20(sellToken).safeTransferFrom(msg.sender, address(this), sellAmount);
        ERC20(buyToken).safeTransfer(msg.sender, buyAmount);

        updateInvariant();

        emit Swap(sellToken, buyToken, sellAmount, buyAmount);
    }

    function updateInvariant() internal {
        invariant = ERC20(tokenA).balanceOf(address(this)) * ERC20(tokenB).balanceOf(address(this));
    }

    function getBuyAmount(address sellToken, address buyToken, uint256 adjustedAmount, uint256 sellTokenBalance, uint256 buyTokenBalance) internal view returns (uint256) {
        uint256 newSellTokenBalance = sellTokenBalance + adjustedAmount;
        uint256 newBuyTokenBalance = invariant / newSellTokenBalance;
        return buyTokenBalance - newBuyTokenBalance;
    }
}
