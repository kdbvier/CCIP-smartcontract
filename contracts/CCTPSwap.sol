// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

library Path {
    using BytesLib for bytes;

    /// @dev The length of the bytes encoded address
    uint256 private constant ADDR_SIZE = 20;
    /// @dev The length of the bytes encoded fee
    uint256 private constant FEE_SIZE = 3;

    /// @dev The offset of a single token address and pool fee
    uint256 private constant NEXT_OFFSET = ADDR_SIZE + FEE_SIZE;
    /// @dev The offset of an encoded pool key
    uint256 private constant POP_OFFSET = NEXT_OFFSET + ADDR_SIZE;
    /// @dev The minimum length of an encoding that contains 2 or more pools
    uint256 private constant MULTIPLE_POOLS_MIN_LENGTH = POP_OFFSET + NEXT_OFFSET;

    /// @notice Returns true iff the path contains two or more pools
    /// @param path The encoded swap path
    /// @return True if path contains two or more pools, otherwise false
    function hasMultiplePools(bytes memory path) internal pure returns (bool) {
        return path.length >= MULTIPLE_POOLS_MIN_LENGTH;
    }

    /// @notice Returns the number of pools in the path
    /// @param path The encoded swap path
    /// @return The number of pools in the path
    function numPools(bytes memory path) internal pure returns (uint256) {
        // Ignore the first token address. From then on every fee and token offset indicates a pool.
        return ((path.length - ADDR_SIZE) / NEXT_OFFSET);
    }

    /// @notice Decodes the first pool in path
    /// @param path The bytes encoded swap path
    /// @return tokenA The first token of the given pool
    /// @return tokenB The second token of the given pool
    /// @return fee The fee level of the pool
    function decodeFirstPool(bytes memory path)
        internal
        pure
        returns (
            address tokenA,
            address tokenB,
            uint24 fee
        )
    {
        tokenA = path.toAddress(0);
        fee = path.toUint24(ADDR_SIZE);
        tokenB = path.toAddress(NEXT_OFFSET);
    }

    /// @notice Gets the segment corresponding to the first pool in the path
    /// @param path The bytes encoded swap path
    /// @return The segment containing all data necessary to target the first pool in the path
    function getFirstPool(bytes memory path) internal pure returns (bytes memory) {
        return path.slice(0, POP_OFFSET);
    }

    /// @notice Skips a token + fee element from the buffer and returns the remainder
    /// @param path The swap path
    /// @return The remaining token + fee elements in the path
    function skipToken(bytes memory path) internal pure returns (bytes memory) {
        return path.slice(NEXT_OFFSET, path.length - NEXT_OFFSET);
    }
}
library BytesLib {
    function slice(
        bytes memory _bytes,
        uint256 _start,
        uint256 _length
    ) internal pure returns (bytes memory) {
        require(_length + 31 >= _length, 'slice_overflow');
        require(_start + _length >= _start, 'slice_overflow');
        require(_bytes.length >= _start + _length, 'slice_outOfBounds');

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
                case 0 {
                    // Get a location of some free memory and store it in tempBytes as
                    // Solidity does for memory variables.
                    tempBytes := mload(0x40)

                    // The first word of the slice result is potentially a partial
                    // word read from the original array. To read it, we calculate
                    // the length of that partial word and start copying that many
                    // bytes into the array. The first word we copy will start with
                    // data we don't care about, but the last `lengthmod` bytes will
                    // land at the beginning of the contents of the new array. When
                    // we're done copying, we overwrite the full first word with
                    // the actual length of the slice.
                    let lengthmod := and(_length, 31)

                    // The multiplication in the next line is necessary
                    // because when slicing multiples of 32 bytes (lengthmod == 0)
                    // the following copy loop was copying the origin's length
                    // and then ending prematurely not copying everything it should.
                    let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                    let end := add(mc, _length)

                    for {
                        // The multiplication in the next line has the same exact purpose
                        // as the one above.
                        let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                    } lt(mc, end) {
                        mc := add(mc, 0x20)
                        cc := add(cc, 0x20)
                    } {
                        mstore(mc, mload(cc))
                    }

                    mstore(tempBytes, _length)

                    //update free-memory pointer
                    //allocating the array padded to 32 bytes like the compiler does now
                    mstore(0x40, and(add(mc, 31), not(31)))
                }
                //if we want a zero-length slice let's just return a zero-length array
                default {
                    tempBytes := mload(0x40)
                    //zero out the 32 bytes slice we are about to return
                    //we need to do it because Solidity does not garbage collect
                    mstore(tempBytes, 0)

                    mstore(0x40, add(tempBytes, 0x20))
                }
        }

        return tempBytes;
    }

    function toAddress(bytes memory _bytes, uint256 _start) internal pure returns (address) {
        require(_start + 20 >= _start, 'toAddress_overflow');
        require(_bytes.length >= _start + 20, 'toAddress_outOfBounds');
        address tempAddress;

        assembly {
            tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
        }

        return tempAddress;
    }

    function toUint24(bytes memory _bytes, uint256 _start) internal pure returns (uint24) {
        require(_start + 3 >= _start, 'toUint24_overflow');
        require(_bytes.length >= _start + 3, 'toUint24_outOfBounds');
        uint24 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x3), _start))
        }

        return tempUint;
    }
}

interface IV3SwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut);

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
    function exactInput(
        ExactInputParams calldata params
    ) external payable returns (uint256 amountOut);

    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }
    function exactOutputSingle(
        ExactOutputSingleParams calldata params
    ) external payable returns (uint256 amountIn);

    struct ExactOutputParams {
        bytes path;
        address recipient;
        uint256 amountOut;
        uint256 amountInMaximum;
    }
    function exactOutput(
        ExactOutputParams calldata params
    ) external payable returns (uint256 amountIn);

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external;

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to
    ) external payable returns (uint256 amountOut);
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to
    ) external payable returns (uint256 amountIn);

    function WETH9() external view returns (address);
}

interface IUniswapV2Router02 {
    function WETH() external pure returns (address);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function quote(
        uint amountA,
        uint reserveA,
        uint reserveB
    ) external pure returns (uint amountB);
    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) external pure returns (uint amountOut);
    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
}

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint amount) external;
}
interface IMessageTransmitter {
    function receiveMessage(
        bytes calldata message,
        bytes calldata attestation
    ) external returns (bool success);
}
interface ITokenMessenger {
  function depositForBurn(
    uint256 amount,
    uint32 destinationDomain,
    bytes32 mintRecipient,
    address burnToken
  ) external returns (uint64 _nonce);
}

contract CCTPSwap is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Path for bytes; // Using Path library for bytes
    using BytesLib for bytes;

    IUniswapV2Router02 public v2Router;
    IV3SwapRouter public v3Router;
    IMessageTransmitter public messageTransmitter;
    ITokenMessenger public tokenMessenger;

    address public immutable USDC;
    address public immutable weth;
    address public executor;
    error FailedCall();

    struct ReceiverSwapData {
        address finalToken;
        address userReceiver;
        uint256 minAmountOut;
        uint256 minAmountOutV2Swap;
        bool isV2;
        bool unwrapETH;
        bytes path;
        address[] v2Path;
    }
    struct InitialSwapData {
        address tokenIn; // Token you're sending for a crosschain swap
        uint256 amountIn; // For the token you send
        uint256 minAmountOutV2Swap; // For the token you send
        uint256 minAmountOutV3Swap;
        bool swapTokenInV2First; // Can be true = swap to v2 or false = swap to v3 towards WETH then we do WETH to USDC in v3, this will be false if the path is weth
        bool unwrappedETH; // Users may want to use WETH directly instead of ETH
        bytes v3InitialSwap; // This is the path for token to USDC can be just WETH to USDC or TOKEN to WETH to USDC
    }

    modifier onlyExecutor() {
        require(msg.sender == executor, "not executor");
        _;
    }

    //////////================= Events ====================================================
    event SwapFromUSDC(
        address indexed receiver,
        address indexed token,
        uint256 amountIn,
        uint256 time
    );

    event ExecutorUpdated(
        address indexed oldExecutor,
        address indexed newExecutor
    );

    constructor(
        address _v3Router,
        address _v2Router,
        address _executor,
        address _usdc,
        address _weth,
        address _transmitter,
        address _messenger
    ) Ownable(msg.sender) {
        v3Router = IV3SwapRouter(_v3Router);
        v2Router = IUniswapV2Router02(_v2Router);
        executor = _executor;
        USDC = _usdc;
        weth = _weth;
        messageTransmitter = IMessageTransmitter(_transmitter);
        tokenMessenger = ITokenMessenger(_messenger);
    }
    /**
     * @notice Extracts the last token address from a given Uniswap V3 path.
     * @param _path The bytes array representing the encoded Uniswap V3 swap path.
     * @return The address of the last token in the path.
     */
    function getLastAddressPath(bytes memory _path) public pure returns (address) {
        // Get the number of pools in the path. Each pool represents a swap step.
        uint256 pools = _path.numPools();
        
        // Declare a variable to store the last token address.
        address last;
        
        // Loop through each pool in the path to decode the tokens.
        for (uint256 i = 0; i < pools; i++) {
            // Decode the first pool in the path to get the output token of the pool.
            // The decodeFirstPool function returns the input token, fee, and output token.
            (, address tokenOut,) = _path.decodeFirstPool();
            
            // Update the last token address with the output token of the current pool.
            last = tokenOut;
            
            // Skip to the next pool in the path by removing the already decoded pool data.
            _path = _path.skipToken();
        }
        
        // Return the last token address in the path.
        return last;
    }
    // Approves from this to the target contract unlimited tokens
    function checkAndApproveAll(address _token, address _target, uint256 _amountToCheck) internal {
        if (IERC20(_token).allowance(address(this), _target) < _amountToCheck) {
            IERC20(_token).safeIncreaseAllowance(_target, _amountToCheck);
            IERC20(_token).safeIncreaseAllowance(_target, _amountToCheck);
        }
    }
    function swapInitialData(
        InitialSwapData memory _initialSwapData
    ) internal returns(uint256 USDCOut) {
        if (_initialSwapData.tokenIn == USDC) {
            // Step a)
            USDCOut = _initialSwapData.amountIn;
        } else {
            // Step b)
            if (_initialSwapData.swapTokenInV2First) {
                require(_initialSwapData.tokenIn != weth, "Token in must not be WETH");
                checkAndApproveAll(_initialSwapData.tokenIn, address(v2Router), _initialSwapData.amountIn);

                // Swap ReceiverSwapData.finalToken to ETH via V2, then to USDC via uniswap V3
                address[] memory path = new address[](2);
                path[0] = _initialSwapData.tokenIn;
                path[1] = weth;
                uint256 wethBalanceBefore = IERC20(weth).balanceOf(address(this));
                v2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    _initialSwapData.amountIn,
                    _initialSwapData.minAmountOutV2Swap,
                    path,
                    address(this),
                    block.timestamp + 1 hours
                );
                uint256 wethBalanceAfter = IERC20(weth).balanceOf(address(this));
                uint256 wethOut = wethBalanceAfter - wethBalanceBefore;
                _initialSwapData.amountIn = wethOut; // This is updated for the next step
                checkAndApproveAll(weth, address(v3Router), wethOut);
            } else {
                checkAndApproveAll(_initialSwapData.tokenIn, address(v3Router), _initialSwapData.amountIn);
            }
            // Step c)
            uint256 beforeSendingUsdc = IERC20(USDC).balanceOf(address(this));
            IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter.ExactInputParams(
                _initialSwapData.v3InitialSwap, address(this), _initialSwapData.amountIn, _initialSwapData.minAmountOutV3Swap
            );

            // Swap ReceiverSwapData.finalToken to ETH via V3, then to USDC via uniswap V3
            USDCOut = v3Router.exactInput( params );

            uint256 afterSendingUsdc = IERC20(USDC).balanceOf(address(this));
            require(afterSendingUsdc > beforeSendingUsdc, "Must swap into USDC");
        }
        // Send the fee
        // uint256 feeAmount = USDCOut * swapFee / (feeBps * 100);
        // IERC20(USDC).safeTransfer(feeReceiver, feeAmount);
        // USDCOut = USDCOut - feeAmount;
    }
    function swapFromUSDC(
        bytes calldata _message,
        bytes calldata _attestation,
        address _outputToken,
        uint256 _amountIn,
        uint256 _minAmountOut,
        uint256 _minAmountOutV2Swap,
        bool _useV2,
        address[] memory _pathV2,
        bytes memory _pathV3,
        address to,
        bool unwrapETH
    ) public nonReentrant onlyExecutor {
        require(
            messageTransmitter.receiveMessage(_message, _attestation),
            "receiveMessage() failed"
        );
        // USDC -> Token
        if (_outputToken == USDC) {
            IERC20(USDC).safeTransfer(to, _amountIn);
            emit SwapFromUSDC(to, USDC, _amountIn, block.timestamp);
            return;
        }

        // 1. Swap USDC to ETH (and/or final token) on v3
        IERC20(USDC).approve(address(v3Router), _amountIn);
        IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter
            .ExactInputParams(
                _pathV3,
                _useV2 || unwrapETH ? address(this) : to,
                _amountIn,
                _minAmountOut
            );

        uint256 wethOrFinalTokenOut = v3Router.exactInput(params);

        if (_useV2) {
            IERC20(weth).approve(address(v2Router), wethOrFinalTokenOut);
            v2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                wethOrFinalTokenOut,
                _minAmountOutV2Swap,
                _pathV2,
                unwrapETH ? address(this) : to,
                block.timestamp + 1 hours
            );
        }

        if (unwrapETH) {
            uint256 wethBalance = IERC20(weth).balanceOf(address(this));
            IWETH(weth).withdraw(wethBalance);
            // payable(receiverData.userReceiver).transfer(address(this).balance);
            (bool success, ) = to.call{value: address(this).balance}("");
            if (!success) {
                revert FailedCall();
            }
        }
        emit SwapFromUSDC(to, _outputToken, _amountIn, block.timestamp);
    }
    function swapToUSDCAndBurn(
        InitialSwapData calldata _initialSwapData,
        uint32 destinationDomain,
        bytes32 mintRecipient
    ) external payable nonReentrant {
        InitialSwapData memory initialSwapData = _initialSwapData;
        if (
            !_initialSwapData.unwrappedETH && _initialSwapData.tokenIn == weth
        ) {
            IWETH(weth).deposit{value: msg.value - _initialSwapData.amountIn}(); // _initialSwapData.amountIn will be the CCIP fee when using eth
            initialSwapData.amountIn = msg.value - initialSwapData.amountIn;
        } else {
            // To take into consideration transfer fees
            uint256 beforeSending = IERC20(_initialSwapData.tokenIn).balanceOf(
                address(this)
            );
            IERC20(_initialSwapData.tokenIn).safeTransferFrom(
                msg.sender,
                address(this),
                _initialSwapData.amountIn
            );
            uint256 afterSending = IERC20(_initialSwapData.tokenIn).balanceOf(
                address(this)
            );
            initialSwapData.amountIn = afterSending - beforeSending;
        }
        address outputToken = getLastAddressPath(initialSwapData.v3InitialSwap);
        require(outputToken == USDC, 'Must swap to USDC');
        uint256 USDCOut = swapInitialData(initialSwapData);
        tokenMessenger.depositForBurn(USDCOut, destinationDomain, mintRecipient, USDC);
    }

    function setExecutor(address _newExecutor) external onlyOwner {
        emit ExecutorUpdated(executor, _newExecutor);
        executor = _newExecutor;
    }

    function recoverStuckTokens(address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(owner(), amount);
    }

    receive() external payable {}

    fallback() external payable {}
}
