pragma solidity >=0.4.21 <0.8.0;

// Deposit & Withdraw Funds
// Manage ORders - make/cancel
// Hanfle Trades - charge fees

import "./Token.sol";
import 'openzeppelin-solidity/contracts/math/SafeMath.sol';

contract Exchange {
	using SafeMath for uint256;

	// Variables 
	// [X] Set the fee account
	address public feeAccount; // this is the acc that receives exchange fees
	uint256 public feePercent; // this is the fee percent
	address constant ETHER = address(0); // store Ether in tokens mapping with a blank address
	mapping(address => mapping(address => uint256)) public tokens;
	// keeps a mapping of all tokens deposited -> 1st key: token address, then the 2nd key: user address, and the final value:is the number of tokens held by the user

	// A way to store the order
	mapping(uint256 => _Order) public orders;
	uint256 public orderCount; // keeps track of the orders
	mapping(uint256 => bool) public orderCancelled;
	mapping(uint256 => bool) public orderFilled;

	// Events
	event Deposit(address token, address user, uint256 amount, uint256 balance);
	event Withdraw(address token, address user, uint256 amount, uint256 balance);

	// Order event
	event Order(
		uint256 id, 
		address user,
		address tokenGet, 
		uint256 amountGet,
		address tokenGive,
		uint256 amountGive,
		uint256 timestamp
		);

	event Cancel(
		uint256 id, 
		address user,
		address tokenGet, 
		uint256 amountGet,
		address tokenGive,
		uint256 amountGive,
		uint256 timestamp
		);

	event Trade(
		uint256 id, 
		address user,
		address tokenGet, 
		uint256 amountGet,
		address tokenGive,
		uint256 amountGive,
		address userFill, 
		uint256 timestamp
		);

	// Structs
	// A way to model the order 
	struct _Order {
		// the reason why _Order has an underscore is so that it won't conflict with the event we want to emit
		uint256 id;
		address user; // user address—the person who created the order
		address tokenGet; // token they want to get
		uint256 amountGet; // amount they want to get
		address tokenGive; // token they wanna give in exchange
		uint256 amountGive; // amount of tokens they'll give
		uint256 timestamp;
	}

	constructor (address _feeAccount, uint256 _feePercent) public {
		feeAccount = _feeAccount;
		feePercent = _feePercent;
	}

	// Fallback: reverts if ETH is sent to this smart contract by mistake
	function() external {
		revert();
	}

	// [X] Deposit Ether
	function depositEther() payable public {
		tokens[ETHER][msg.sender] = tokens[ETHER][msg.sender].add(msg.value);
		emit Deposit(ETHER, msg.sender, msg.value, tokens[ETHER][msg.sender]);

	}

	function withdrawEther(uint256 _amount) public {
		require(tokens[ETHER][msg.sender] >= _amount);
		tokens[ETHER][msg.sender] = tokens[ETHER][msg.sender].sub(_amount);
		msg.sender.transfer(_amount);
		emit Withdraw(ETHER, msg.sender, _amount, tokens[ETHER][msg.sender]);
	}

	// [X] Deposit Tokens
	function depositToken(address _token, uint256 _amount) public {
		// Tells which token to send, and how much	

		require(_token != ETHER);
		// Don't allow Ether deposits

		require(Token(_token).transferFrom(msg.sender, address(this), _amount));	
		// Send tokens to this contract

		tokens[_token][msg.sender] = tokens[_token][msg.sender].add(_amount);
		// Manage deposits - update
		// Takes the mapping, passes the token address, then passes the user address, and updates it

		emit Deposit(_token, msg.sender, _amount, tokens[_token][msg.sender]);
		// Emit an event		
	}

	function withdrawToken(address _token, uint256 _amount) public {

		// require that this is not an ether address
		require(_token != ETHER); 

		// make sure they have enough tokens to withdraw
		require(tokens[_token][msg.sender] >= _amount); 

		tokens[_token][msg.sender] = tokens[_token][msg.sender].sub(_amount);
		require(Token(_token).transfer(msg.sender, _amount));
		emit Withdraw(_token, msg.sender, _amount, tokens[_token][msg.sender]);
	}

	function balanceOf(address _token, address _user) public view returns (uint256) { 
	// view is a reader function that will return a value for us

		return tokens[_token][_user];
	}

	// Add the order to storage
	function makeOrder(address _tokenGet, uint256 _amountGet, address _tokenGive, uint256 _amountGive) public {
	    orderCount = orderCount.add(1);
	    orders[orderCount] = _Order(orderCount, msg.sender, _tokenGet, _amountGet, _tokenGive, _amountGive, now);
	    emit Order(orderCount, msg.sender, _tokenGet, _amountGet, _tokenGive, _amountGive, now);
	}

	function cancelOrder(uint256 _id) public {
	    _Order storage _order = orders[_id];
	    require(address(_order.user) == msg.sender);
	    require(_order.id == _id); // The order must exist
	    orderCancelled[_id] = true;
	    emit Cancel(_order.id, msg.sender, _order.tokenGet, _order.amountGet, _order.tokenGive, _order.amountGive, now);
	} 

	function fillOrder(uint256 _id) public {
		require(_id > 0 && _id <= orderCount); // greater than zero, and it's less than the total order count
		require(!orderFilled[_id]);
		require(!orderCancelled[_id]);
		// basically we don't want the order to be either cancelled or filled

		_Order storage _order = orders[_id]; // Fetch the Order
		_trade(_order.id, _order.user, _order.tokenGet, _order.amountGet, _order.tokenGive, _order.amountGive);
		orderFilled[_order.id] = true;

		// Mark the Order as Filled
	}  


	function _trade(uint256 _orderId, address _user, address _tokenGet, uint256 _amountGet, address _tokenGive, uint256 _amountGive) internal {
		// Fee paid by the user that fills the order 
		uint256 _feeAmount = _amountGet.mul(feePercent).div(100); // multiply the amount by the fee percentage then divide it by 100 to get the value

		// Execute Trade 
		tokens[_tokenGet][msg.sender] = tokens[_tokenGet][msg.sender].sub(_amountGet.add(_feeAmount)); // subtracting the total plus fees
		tokens[_tokenGet][_user] = tokens[_tokenGet][_user].add(_amountGet);
		tokens[_tokenGet][feeAccount] = tokens[_tokenGet][feeAccount].add(_feeAmount);
		tokens[_tokenGive][_user] = tokens[_tokenGive][_user].sub(_amountGive);
		tokens[_tokenGive][msg.sender] = tokens[_tokenGive][msg.sender].add(_amountGive);
		// this block of code is basically how the transactions work——so we have to get token1 from msg.sender (subtract) and give it to the _user (add)
		// we then have to get token2 (as a mode of payment) from _user (subtract) and send it to msg.sender (add)
		// msg.sender is the person filling the order, while _user is the person who created the order

		// Emit a trade event
		emit Trade(_orderId, _user, _tokenGet, _amountGet, _tokenGive, _amountGive, msg.sender, now);

	}




}




// TO DO LIST 
// [ ] Fill Order
// [ ] Charge Fees 