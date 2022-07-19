pragma solidity =0.5.16;
import './interfaces/IUniswapV2Factory.sol';

contract Demo{
    function getData(address factory, address tokenA, address tokenB) public view returns(address) {
        return IUniswapV2Factory(factory).getPair(tokenA, tokenB);
    }
}