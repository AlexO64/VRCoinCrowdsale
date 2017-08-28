pragma solidity ^0.4.15;

contract ERC20Interface
{
    function totalSupply() public constant returns (uint256);
    function balanceOf(address owner) public constant returns (uint256);
    function transfer(address to, uint256 value) public returns (bool);
    function transferFrom(address from, address to, uint256 value) public returns (bool);
    function approve(address spender, uint256 value) public returns (bool);
    function allowance(address owner, address spender) public constant returns (uint256);
    }

contract VRCoinCrowdsale
{
    // Information about a single period
    struct Period
    {
        uint start;
        uint end;
        uint priceInWei;
    }

    // Some constant about our expected token distribution
    uint public constant VRCOIN_DECIMALS = 4;
    uint public constant TOTAL_TOKENS_TO_DISTRIBUTE = 50000000 * (10 ** VRCOIN_DECIMALS); // 50,000,000 VRCoins

    address public owner; // The owner of the crowdsale
    bool public hasStarted; // Has the crowdsale started?
    Period[] public periods; // The configured periods for this crowdsale
    ERC20Interface public tokenWallet; // The token wallet contract used for this crowdsale

    // Fired once the sale starts
    event Start(uint timestamp);

    // Fired whenever a contribution is made
    event Contribution(address indexed from, uint weiContributed, uint tokensReceived);

    function VRCoinCrowdsale(address walletAddress)
    {
        // Setup the owner and wallet
        owner = msg.sender;
        tokenWallet = ERC20Interface(walletAddress);

        // Make sure the provided token has the expected number of tokens to distribute
        require(tokenWallet.totalSupply() == TOTAL_TOKENS_TO_DISTRIBUTE);

        // Make sure the owner actually controls all the tokens
        require(tokenWallet.balanceOf(owner) == TOTAL_TOKENS_TO_DISTRIBUTE);

        // We haven't started yet
        hasStarted = false;

        // Setup the distribution schedule
        Period memory p;

        // The multiplier necessary to change a coin amount to the token amount
        uint coinToTokenFactor = 10 ** VRCOIN_DECIMALS;

        p.start = 1505001600; // Midnight, Sept 10, 2017 UTC
        p.end = 1505433600; // Midnight, Sept 15, 2017 UTC
        p.priceInWei = (1 ether) / (750 * coinToTokenFactor); // 1 ETH = 750 VRCoin
        periods.push(p);

        p.start = 1507593600; // Midnight, Oct 10, 2017 UTC
        p.end = 1508457600; // Midnight, Oct 20, 2017 UTC
        p.priceInWei = (1 ether) / (650 * coinToTokenFactor); // 1 ETH = 650 VRCoin
        periods.push(p);

        p.start = 1510704000; // Midnight, Nov 15, 2017 UTC
        p.end = 1510876800; // Midnight, Nov 17, 2017 UTC
        p.priceInWei = (1 ether) / (600 * coinToTokenFactor); // 1 ETH = 600 VRCoin
        periods.push(p);

        p.start = 1510963200; // Midnight, Nov 18, 2017 UTC
        p.end = 1511136000; // Midnight, Nov 20, 2017 UTC
        p.priceInWei = (1 ether) / (550 * coinToTokenFactor); // 1 ETH = 550 VRCoin
        periods.push(p);

        p.start = 1511395200; // Midnight, Nov 23, 2017 UTC
        p.end = 1512864000; // Midnight, Dec 10, 2017 UTC
        p.priceInWei = (1 ether) / (500 * coinToTokenFactor); // 1 ETH = 500 VRCoin
        periods.push(p);
    }

    // Start the crowdsale
    function startSale()
    {
        // Only the owner can do this
        require(msg.sender == owner);
        
        // Cannot start if already started
        require(hasStarted == false);

        // Attempt to transfer all tokens to the crowdsale contract
        // The owner needs to approve() the transfer of all tokens to this contract
        if (!tokenWallet.transferFrom(owner, this, TOTAL_TOKENS_TO_DISTRIBUTE))
        {
            // Something has gone wrong, the owner no longer controls all the tokens?
            // We cannot proceed
            revert();
        }

        // Sanity check: verify the crowdsale controls all tokens
        require(tokenWallet.balanceOf(this) == TOTAL_TOKENS_TO_DISTRIBUTE);

        // The sale can begin
        hasStarted = true;

        // Fire event that the sale has begun
        Start(block.timestamp);
    }

    // Allow the current owner to change the owner of the crowdsale
    function changeOwner(address newOwner) public
    {
        // Only the owner can do this
        require(msg.sender == owner);

        // Change the owner
        owner = newOwner;
    }

    // Allow the owner to change the price for a period
    // But only if the sale has not begun yet
    function changePeriodPrice(uint period, uint newWeiPrice) public
    {
        // Only the owner can do this
        require(msg.sender == owner);
        
        // We can change period details as long as the sale hasn't started yet
        require(hasStarted == false);

        // Make sure the period is valid
        require(period >= 0 && period < periods.length);

        // Change the price for this period
        periods[period].priceInWei = newWeiPrice;
    }

    // Allow the owner to change the start/end time for a period
    // But only if the sale has not begun yet
    function changePeriodTime(uint period, uint start, uint end) public
    {
        // Only the owner can do this
        require(msg.sender == owner);

        // We can change period details as long as the sale hasn't started yet
        require(hasStarted == false);

        // Make sure the period is valid
        require(period >= 0 && period < periods.length);

        // Make sure the input is valid
        require(start < end);

        // If this period isn't the first
        // Then, the start can't overlap the end of the previous period
        if (period > 0)
        {
            require(start > periods[period-1].end);
        }

        // If this period isn't the last
        // Then, the end can't overlap the start of the next period
        if (period < (periods.length-1))
        {
            require(end < periods[period+1].start);
        }

        // Everything checks out, update the period start/end time
        periods[period].start = start;
        periods[period].end = end;
    }

    // Get the current period
    // Returns -1 if we are between periods, or if the sale is over
    function getCurrentPeriod() public constant 
        returns(int)
    {
        // For each period
        for (uint i = 0; i < periods.length; ++i)
        {
            // Check if we are in the range of this period
            if (block.timestamp >= periods[i].start && block.timestamp <= periods[i].end)
            {
                // This is our current period
                return int(i);
            }
        }

        // Otherwise, we aren't in any period right now
        return -1;
    }

    // Allow the owner to withdraw all the tokens remaining after the
    // crowdsale is over
    function withdrawTokensRemaining() public
        returns (bool)
    {
        // Only the owner can do this
        require(msg.sender == owner);

        // Get the ending timestamp of the crowdsale
        uint crowdsaleEnd = periods[periods.length-1].end;

        // The crowsale must be over to perform this operation
        require(block.timestamp > crowdsaleEnd);

        // Get the remaining tokens owned by the crowdsale
        uint tokensRemaining = getTokensRemaining();

        // Transfer them all to the owner
        return tokenWallet.transfer(owner, tokensRemaining);
    }

    // Allow the owner to withdraw all ether from the contract after the
    // crowdsale is over
    function withdrawEtherRemaining() public
        returns (bool)
    {
        // Only the owner can do this
        require(msg.sender == owner);

        // Get the ending timestamp of the crowdsale
        uint crowdsaleEnd = periods[periods.length-1].end;

        // The crowsale must be over to perform this operation
        require(block.timestamp > crowdsaleEnd);

        // Transfer them all to the owner
        owner.transfer(this.balance);

        return true;
    }

    // Check how many tokens are remaining for distribution
    function getTokensRemaining() public constant
        returns (uint256)
    {
        return tokenWallet.balanceOf(this);
    }

    // Calculate how many tokens can be distributed for the given contribution
    function getTokensForContribution(uint weiContribution) public constant 
        returns(uint tokenAmount, uint weiRemainder)
    {
        // Get the current period
        int period = getCurrentPeriod();

        // Make sure we are in a valid period right now
        require(period >= 0);

        // Get the price for this current period
        uint periodPriceInWei = periods[uint(period)].priceInWei;

        // Return the amount of tokens that can be purchased
        // And the amount of wei that would be left over
        tokenAmount = weiContribution / periodPriceInWei;
        weiRemainder = weiContribution % periodPriceInWei;
    }

    // Allow a user to contribute to the crowdsale
    function contribute() public payable
    {
        // Cannot contribute if the sale hasn't started
        require(hasStarted == true);

        // Calculate the tokens to be distributed based on the contribution amount
        var (tokenAmount, weiRemainder) = getTokensForContribution(msg.value);

        // Need to contribute enough for at least 1 token
        require(tokenAmount > 0);
        
        // Sanity check: make sure the remainder is less or equal to what was sent to us
        require(weiRemainder <= msg.value);

        // Make sure there are enough tokens left to buy
        uint tokensRemaining = getTokensRemaining();
        require(tokensRemaining >= tokenAmount);

        // Transfer the token amount from the crowd sale's token wallet to the
        // sender's token wallet
        if (!tokenWallet.transfer(msg.sender, tokenAmount))
        {
            // Unable to transfer funds, abort transaction
            revert();
        }

        // Return the remainder to the sender
        msg.sender.transfer(weiRemainder);

        // Since we refunded the remainder, the actual contribution is the amount sent
        // minus the remainder
        uint actualContribution = msg.value - weiRemainder;

        // Record the event
        Contribution(msg.sender, actualContribution, tokenAmount);
    }
}