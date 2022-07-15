// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC20.sol";

library Babylonian {
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
        // else z = 0
    }
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IUniswapV2Router02 {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}

interface IUniswapV2Pair {
    function totalSupply() external view returns (uint256);

    function token0() external pure returns (address);

    function token1() external pure returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        );
}

contract Dal_In is Ownable {
    IUniswapV2Factory public pancakeswapFactoryAddress; // mainnet 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73 testnet 0xB7926C0430Afb07AA7DEfDE6DA862aE0Bde767bc

    IUniswapV2Router02 public pancakeswapRouter; // mainnet 0x10ED43C718714eb63d5aA57B78B54704E256024E testnet 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3

    address public wTokenAddress; // mainnet 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c testnet 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd

    uint256 private constant deadline = 0xf000000000000000000000000000000000000000000000000000000000000000;

    bool public stopped = false;

    constructor(
        address _factory,
        address _router,
        address _wTokenAddress
    ) {
        pancakeswapFactoryAddress = IUniswapV2Factory(_factory);
        pancakeswapRouter = IUniswapV2Router02(_router);
        wTokenAddress = _wTokenAddress;
    }

    event DalIn(address sender, address pool, uint256 tokensRec);

    // circuit breaker modifiers
    modifier stopInEmergency() {
        if (stopped) {
            revert("Temporarily Paused");
        } else {
            _;
        }
    }

    function dalIn(address _pairAddress, uint256 _minPoolTokens) external payable stopInEmergency returns (uint256) {
        (address _ToUniswapToken0, address _ToUniswapToken1) = _getPairTokens(_pairAddress);

        uint256 amountIn;

        address tokenTo = _ToUniswapToken0;

        if (wTokenAddress != _ToUniswapToken0 && wTokenAddress != _ToUniswapToken1) {
            amountIn = _token2Token(wTokenAddress, tokenTo, msg.value);
        } else {
            tokenTo = wTokenAddress;
            amountIn = msg.value;
        }

        uint256 LPBought = _performDalIn(tokenTo, _pairAddress, amountIn);

        require(LPBought >= _minPoolTokens, "High Slippage");

        emit DalIn(msg.sender, _pairAddress, LPBought);

        IERC20(_pairAddress).transfer(msg.sender, LPBought);

        return LPBought;
    }

    function _performDalIn(
        address _FromTokenContractAddress,
        address _pairAddress,
        uint256 _amount
    ) internal returns (uint256) {
        (address _ToUniswapToken0, address _ToUniswapToken1) = _getPairTokens(_pairAddress);

        // divide intermediate into appropriate amount to add liquidity
        (uint256 token0Bought, uint256 token1Bought) = _swapIntermediate(_FromTokenContractAddress, _ToUniswapToken0, _ToUniswapToken1, _amount);

        return _uniDeposit(_ToUniswapToken0, _ToUniswapToken1, token0Bought, token1Bought);
    }

    function _uniDeposit(
        address _ToUnipoolToken0,
        address _ToUnipoolToken1,
        uint256 token0Bought,
        uint256 token1Bought
    ) internal returns (uint256) {
        uint256 amountA;
        uint256 amountB;
        uint256 LP;
        if (_ToUnipoolToken0 == wTokenAddress || _ToUnipoolToken1 == wTokenAddress) {
            if (_ToUnipoolToken0 == wTokenAddress) {
                IERC20(_ToUnipoolToken1).approve(address(pancakeswapRouter), token1Bought);
                (amountB, amountA, LP) = pancakeswapRouter.addLiquidityETH{value: token0Bought}(_ToUnipoolToken1, token1Bought, 1, 1, address(this), deadline);
            } else {
                IERC20(_ToUnipoolToken0).approve(address(pancakeswapRouter), token0Bought);
                (amountA, amountB, LP) = pancakeswapRouter.addLiquidityETH{value: token1Bought}(_ToUnipoolToken0, token0Bought, 1, 1, address(this), deadline);
            }
        } else {
            IERC20(_ToUnipoolToken0).approve(address(pancakeswapRouter), token0Bought);
            IERC20(_ToUnipoolToken1).approve(address(pancakeswapRouter), token1Bought);
            (amountA, amountB, LP) = pancakeswapRouter.addLiquidity(_ToUnipoolToken0, _ToUnipoolToken1, token0Bought, token1Bought, 1, 1, address(this), deadline);
        }

        //Returning Residue in token0, if any.
        if (token0Bought - amountA > 0) {
            safeTransfer(msg.sender, _ToUnipoolToken0, token0Bought - amountA);
        }

        //Returning Residue in token1, if any
        if (token1Bought - amountB > 0) {
            safeTransfer(msg.sender, _ToUnipoolToken1, token1Bought - amountB);
        }

        return LP;
    }

    function _swapIntermediate(
        address _toContractAddress,
        address _ToUnipoolToken0,
        address _ToUnipoolToken1,
        uint256 _amount
    ) internal returns (uint256 token0Bought, uint256 token1Bought) {
        IUniswapV2Pair pair = IUniswapV2Pair(pancakeswapFactoryAddress.getPair(_ToUnipoolToken0, _ToUnipoolToken1));

        (uint256 res0, uint256 res1, ) = pair.getReserves();

        if (_toContractAddress == _ToUnipoolToken0) {
            uint256 amountToSwap = calculateSwapInAmount(res0, _amount);
            //if no reserve or a new pair is created
            if (amountToSwap <= 0) amountToSwap = _amount / 2;

            token1Bought = _token2Token(_toContractAddress, _ToUnipoolToken1, amountToSwap);
            token0Bought = _amount - amountToSwap;
        } else {
            uint256 amountToSwap = calculateSwapInAmount(res1, _amount);
            //if no reserve or a new pair is created
            if (amountToSwap <= 0) amountToSwap = _amount / 2;
            token0Bought = _token2Token(_toContractAddress, _ToUnipoolToken0, amountToSwap);
            token1Bought = _amount - amountToSwap;
        }
    }

    function calculateSwapInAmount(uint256 reserveIn, uint256 userIn) internal pure returns (uint256) {
        return (Babylonian.sqrt(reserveIn * ((userIn * 3988000) + (reserveIn * 3988009))) - (reserveIn * 1997)) / 1994;
    }

    /**
    @notice This function is used to swap ERC20 <> ERC20
    @param _FromTokenContractAddress The token address to swap from.
    @param _ToTokenContractAddress The token address to swap to. 
    @param tokens2Trade The amount of tokens to swap
    @return tokenBought The quantity of tokens bought
    */
    function _token2Token(
        address _FromTokenContractAddress,
        address _ToTokenContractAddress,
        uint256 tokens2Trade
    ) internal returns (uint256 tokenBought) {
        if (_FromTokenContractAddress == _ToTokenContractAddress) {
            return tokens2Trade;
        }

        address pair = pancakeswapFactoryAddress.getPair(_FromTokenContractAddress, _ToTokenContractAddress);

        require(pair != address(0), "No Swap Available");
        address[] memory path = new address[](2);
        path[0] = _FromTokenContractAddress;
        path[1] = _ToTokenContractAddress;

        if (_FromTokenContractAddress == wTokenAddress) {
            tokenBought = pancakeswapRouter.swapExactETHForTokens{value: tokens2Trade}(1, path, address(this), deadline)[path.length - 1];
        } else {
            IERC20(path[0]).approve(address(pancakeswapRouter), tokens2Trade);
            tokenBought = pancakeswapRouter.swapExactTokensForTokens(tokens2Trade, 1, path, address(this), deadline)[path.length - 1];
        }
        require(tokenBought > 0, "Error Swapping Tokens 2");
    }

    // - to Pause the contract
    function toggleContractActive() public onlyOwner {
        stopped = !stopped;
    }

    function withdrawTokens(address[] calldata tokens) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == wTokenAddress) {
                payable(owner()).transfer(address(this).balance);
            } else {
                uint256 amount = IERC20(tokens[i]).balanceOf(address(this));
                IERC20(tokens[i]).transfer(owner(), amount);
            }
        }
    }

    function safeTransfer(
        address to,
        address token,
        uint256 amount
    ) internal {
        if (token == wTokenAddress) {
            payable(to).transfer(amount);
        } else {
            IERC20(token).transfer(to, amount);
        }
    }

    function _getPairTokens(address _pairAddress) internal pure returns (address token0, address token1) {
        IUniswapV2Pair uniPair = IUniswapV2Pair(_pairAddress);
        token0 = uniPair.token0();
        token1 = uniPair.token1();
    }

    function getAmountOutIn(uint256 amount_wToken, address pair_token) public view returns (uint256) {
        (address _ToUniswapToken0, address _ToUniswapToken1) = _getPairTokens(pair_token);
        uint256 amountIn = amount_wToken;
        if (wTokenAddress != _ToUniswapToken0 && wTokenAddress != _ToUniswapToken1) {
            address wPair = pancakeswapFactoryAddress.getPair(wTokenAddress, _ToUniswapToken0);
            require(wPair != address(0), "No Swap Available");
            address[] memory wPath = new address[](2);
            wPath[0] = wTokenAddress;
            wPath[1] = _ToUniswapToken0;
            amountIn = pancakeswapRouter.getAmountsOut(amount_wToken, wPath)[wPath.length - 1];
        }

        IUniswapV2Pair pair = IUniswapV2Pair(pancakeswapFactoryAddress.getPair(_ToUniswapToken0, _ToUniswapToken1));
        (uint256 res0, uint256 res1, ) = pair.getReserves();

        uint256 amountToSwap = calculateSwapInAmount(res0, amountIn);
        if (amountToSwap <= 0) amountToSwap = amountIn / 2;
        address[] memory path = new address[](2);
        path[0] = _ToUniswapToken0;
        path[1] = _ToUniswapToken1;
        uint256 token1Bought = pancakeswapRouter.getAmountsOut(amountToSwap, path)[path.length - 1];
        require(token1Bought > 0, "Error Swapping Tokens 2");
        uint256 token0Bought = amountIn - amountToSwap;

        uint256 rate0 = (token0Bought * pair.totalSupply()) / res0;
        uint256 rate1 = (token1Bought * pair.totalSupply()) / res1;

        if (rate0 > rate1) return rate1;
        return rate0;
    }

    receive() external payable {}
}
