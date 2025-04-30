pragma solidity =0.8.20;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

library Structs {
    // Add this struct to the Structs library
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    struct ExactInputParamsWithDeadline {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
}

interface IUniswapV2Pair {
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IDexFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);
    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint) external;
}

interface ISwapRouter {
    function exactInput(Structs.ExactInputParams calldata params) external payable returns (uint256 amountOut);

    function exactInput(
        Structs.ExactInputParamsWithDeadline calldata params
    ) external payable returns (uint256 amountOut);
}

// a library for performing overflow-safe math, courtesy of DappHub (https://github.com/dapphub/ds-math)
library SafeMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, 'ds-math-add-overflow');
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, 'ds-math-sub-underflow');
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, 'divide by zero'); // Solidity automatically throws when dividing by 0
        return a / b;
    }
}

// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
library TransferHelper {
    function safeApprove(address token, address to, uint value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }

    function safeTransferETH(address to, uint value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
    }
}

contract OfficialInstantSwap is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    address public immutable USDC;
    address public immutable WETH;
    address public executor;

    error FailedCall();

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'CSRouter: EXPIRED');
        _;
    }

    modifier onlyExecutor() {
        require(msg.sender == executor, 'not executor');
        _;
    }

    //////////================= Events ====================================================
    event SwapFromUSDC(
        address indexed receiver,
        address indexed token,
        uint256 amountIn,
        uint256 amountOut,
        uint256 time
    );

    event ExecutorUpdated(address indexed oldExecutor, address indexed newExecutor);
    constructor(address _executor, address _usdc, address _weth) Ownable(msg.sender) {
        executor = _executor;
        USDC = _usdc;
        WETH = _weth;
    }

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'CSRouter: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'CSRouter: ZERO_ADDRESS');
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'CSRouter: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'CSRouter: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair

    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to, address factory) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = sortTokens(input, output);
            IUniswapV2Pair pair = IUniswapV2Pair(IDexFactory(factory).getPair(input, output));
            uint amountInput;
            uint amountOutput;
            {
                // scope to avoid stack too deep errors
                (uint reserve0, uint reserve1, ) = pair.getReserves();
                (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
                amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
                amountOutput = getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? IDexFactory(factory).getPair(output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    struct CallStruct {
        uint256 amountIn;
        uint256 amountOutMin;
        address[] path;
        uint256 deadline;
        bool swapWithDeadline;
        address factoryOrSwapRouter;
        bytes encodedPath;
        address to;
    }

    function multicallSwap(CallStruct[] memory _calls) internal {
        uint256 amountOutPreviousSwap = 0;
        for (uint256 i = 0; i < _calls.length; i++) {
            CallStruct memory myCall = _calls[i];
            uint256 amountIn = myCall.amountIn;
            if (i > 0) {
                amountIn = amountOutPreviousSwap;
            }
            address tokenOut = myCall.path[myCall.path.length - 1]; // Token out
            uint256 balanceInitial;
            if (tokenOut == address(0)) {
                balanceInitial = address(this).balance;
            } else {
                balanceInitial = IERC20(tokenOut).balanceOf(address(this));
            }
            bool isLastItem = i == _calls.length - 1;
            if (isLastItem && i > 0) {
                require(
                    _calls[i - 1].path[_calls[i - 1].path.length - 1] == _calls[i].path[0],
                    'CSRouter: Middle Token must be same'
                );
            }

            if (myCall.encodedPath.length == 0) {
                swapV2(
                    amountIn,
                    myCall.amountOutMin,
                    myCall.path,
                    myCall.deadline,
                    myCall.factoryOrSwapRouter,
                    myCall.to
                );
            } else {
                swapV3(
                    amountIn,
                    myCall.amountOutMin,
                    myCall.path,
                    myCall.deadline,
                    myCall.swapWithDeadline,
                    myCall.factoryOrSwapRouter,
                    myCall.encodedPath,
                    myCall.to
                );
            }
            uint256 balanceFinal;
            if (tokenOut == address(0)) {
                balanceFinal = address(this).balance;
            } else {
                balanceFinal = IERC20(tokenOut).balanceOf(address(this));
            }

            amountOutPreviousSwap = balanceFinal - balanceInitial;
        }
    }

    function swapV2(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] memory _path,
        uint256 _deadline,
        address _factory,
        address _to
    ) internal ensure(_deadline) {
        address[] memory path = _path;
        bool isNativeOut = false;
        if (path[1] == address(0)) {
            path[1] = WETH;
            isNativeOut = true;
        }
        address pairContract = IDexFactory(_factory).getPair(path[0], path[1]);
        uint256 balanceFinalTokenBefore = IERC20(path[1]).balanceOf(address(this));

        TransferHelper.safeTransfer(path[0], pairContract, _amountIn);
        _swapSupportingFeeOnTransferTokens(path, address(this), _factory);
        uint256 amountOut = IERC20(path[1]).balanceOf(address(this)) - balanceFinalTokenBefore;
        require(amountOut >= _amountOutMin, 'CSRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        // Transfer token to sender
        if (_to != address(this)) {
            if (isNativeOut) {
                IWETH(WETH).withdraw(amountOut);
                TransferHelper.safeTransferETH(_to, amountOut);
            } else {
                TransferHelper.safeTransfer(path[1], _to, amountOut);
            }
        }
    }

    function swapV3(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] memory _path,
        uint256 _deadline,
        bool _useDeadline,
        address _swapRouter,
        bytes memory _encodedPath,
        address _to
    ) internal ensure(_deadline) {
        require(_path.length >= 2, 'Invalid path length');
        require(_to != address(0), 'Invalid recipient address');
        address[] memory path = _path;
        bool isInputETH = path[0] == address(0);
        bool isOutputETH = path[1] == address(0);
        address inputToken = isInputETH ? WETH : path[0];
        address outputToken = isOutputETH ? WETH : path[1];
        IERC20(inputToken).approve(_swapRouter, _amountIn);
        uint256 amountOut;
        if (_useDeadline) {
            Structs.ExactInputParamsWithDeadline memory inputParams = Structs.ExactInputParamsWithDeadline({
                path: _encodedPath,
                recipient: address(this),
                deadline: _deadline,
                amountIn: _amountIn,
                amountOutMinimum: _amountOutMin
            });
            amountOut = ISwapRouter(_swapRouter).exactInput{value: 0}(inputParams);
        } else {
            Structs.ExactInputParams memory inputParams = Structs.ExactInputParams({
                path: _encodedPath,
                recipient: address(this),
                amountIn: _amountIn,
                amountOutMinimum: _amountOutMin
            });
            amountOut = ISwapRouter(_swapRouter).exactInput{value: 0}(inputParams);
        }
        require(amountOut >= _amountOutMin, 'CSRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        if (_to != address(this)) {
            if (isOutputETH) {
                IWETH(WETH).withdraw(amountOut);
                TransferHelper.safeTransferETH(_to, amountOut);
            } else {
                TransferHelper.safeTransfer(outputToken, _to, amountOut);
            }
        }
    }

    function swapFromUSDC(CallStruct[] memory _swapData) external nonReentrant onlyExecutor {
        // Validate _swapData array
        require(_swapData.length > 0, "Empty swap data");
        
        // Validate first swap must use USDC as input token
        require(_swapData[0].path.length >= 2, "Invalid path length");
        require(_swapData[0].path[0] == USDC, "First token must be USDC");
        require(_swapData[0].amountIn > 0, "Amount must be greater than 0");
        
        // Validate all paths have valid length
        for (uint256 i = 0; i < _swapData.length; i++) {
            require(_swapData[i].path.length >= 2, "Invalid path length");
            require(_swapData[i].to != address(0), "Invalid recipient");
            require(_swapData[i].factoryOrSwapRouter != address(0), "Invalid router/factory");
            require(_swapData[i].deadline >= block.timestamp, "Expired deadline");
            
            // Validate token path continuity between swaps
            if (i > 0) {
                require(
                    _swapData[i-1].path[_swapData[i-1].path.length-1] == _swapData[i].path[0],
                    "Token path mismatch between swaps"
                );
            }
        }
        
        address to = _swapData[_swapData.length - 1].to;
        address outputToken = _swapData[_swapData.length - 1].path[_swapData[_swapData.length - 1].path.length - 1];
        uint256 amountIn = _swapData[0].amountIn;
        if (outputToken == USDC) {
            TransferHelper.safeTransfer(USDC, to, amountIn);
            emit SwapFromUSDC(to, USDC, amountIn, amountIn, block.timestamp);
            return;
        }
        uint256 balanceInitial;
        if (outputToken == address(0)) {
            balanceInitial = address(to).balance;
        } else {
            balanceInitial = IERC20(outputToken).balanceOf(address(to));
        }
        multicallSwap(_swapData);
        uint256 balanceFinal;
        if (outputToken == address(0)) {
            balanceFinal = address(to).balance;
        } else {
            balanceFinal = IERC20(outputToken).balanceOf(address(to));
        }
        uint256 amountOut = balanceFinal - balanceInitial;
        emit SwapFromUSDC(to, outputToken, amountIn, amountOut, block.timestamp);
    }

    function setExecutor(address _newExecutor) external onlyOwner {
        require(_newExecutor != address(0), "Zero address not allowed");
        emit ExecutorUpdated(executor, _newExecutor);
        executor = _newExecutor;
    }

    function recoverStuckTokens(address _token) external onlyOwner {
        require(_token != address(0), "Zero address not allowed");
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(owner(), amount);
    }

    receive() external payable {}

    fallback() external payable {}
}
