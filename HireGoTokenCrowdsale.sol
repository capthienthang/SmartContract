pragma solidity ^0.4.18;

import "./OpenZeppelin/Ownable.sol";
import "./HireGoToken.sol";

/*
 * ICO Start time - 1520164800 - March 4, 2018 12:00:00 PM
 * Default ICO End time - 1527379199 - May 26, 2018 11:59:59 AM
*/
contract HireGoCrowdsale is Ownable {

    using SafeMath for uint;

    HireGoToken public token = new HireGoToken();
    uint totalSupply = token.totalSupply();

    bool public isRefundAllowed;

    uint public presaleStartTime;
    uint public presaleEndTime;
    uint public icoStartTime;
    uint public icoEndTime;

    uint public totalWeiRaised;
    uint internal weiRaised;
    uint public hardCap; // amount of ETH collected, which marks end of crowd sale
    uint public tokensDistributed; // amount of bought tokens
    uint public foundersTokensUnlockTime;


    /*         Bonus variables          */
    uint internal presaleBonus = 135;
    /* * * * * * * * * * * * * * * * * * */

    uint public rate; // how many token units a buyer gets per wei
    uint private icoMinPurchase; // In ETH

    address[] public investors_number;
    address private wallet; // address where funds are collected

    mapping (address => uint) public orderedTokens;
    mapping (address => uint) contributors;

    event FundsWithdrawn(address _who, uint256 _amount);

    modifier hardCapNotReached() {
        require(totalWeiRaised < hardCap);
        _;
    }

    modifier crowdsaleEnded() {
        require(now > icoEndTime);
        _;
    }

    modifier foundersTokensUnlocked() {
        require(now > foundersTokensUnlockTime);
        _;
    }

    modifier crowdsaleInProgress() {
        bool withinPeriod = ((now >= presaleStartTime && now <=presaleEndTime) || (now >= icoStartTime && now <= icoEndTime));
        require(withinPeriod);
        _;
    }

    function HireGoCrowdsale(uint _presaleStartTime,  address _wallet) public {
        require (
          _presaleStartTime > now
        );

        presaleStartTime = _presaleStartTime;
        presaleEndTime = presaleStartTime.add(4 weeks);
        icoStartTime = presaleEndTime.add(1 minutes);
        setIcoEndTime();

        wallet = _wallet;

        rate = 250 szabo; // wei per 1 token (0.00025ETH)

        hardCap = 15000 ether;
        icoMinPurchase = 50 finney; // 0.05 ETH
        isRefundAllowed = false;
    }

    function setIcoEndTime() internal {
          icoEndTime = icoStartTime.add(6 weeks);
          foundersTokensUnlockTime = icoEndTime.add(180 days);
    }

    // fallback function can be used to buy tokens
    function() public payable {
        buyTokens();
    }

    // low level token purchase function
    function buyTokens() public payable crowdsaleInProgress hardCapNotReached {
        require(msg.value > 0);

        // check if the buyer exceeded the funding goal
        calculatePurchaseAndBonuses(msg.sender, msg.value);
    }

    // Returns number of investors
    function getInvestorCount() public view returns (uint) {
        return investors_number.length;
    }

    // Owner can allow or disallow refunds even if soft cap is reached. Should be used in case KYC is not passed.
    // WARNING: owner should transfer collected ETH back to contract before allowing to refund, if he already withdrawn ETH.
    function toggleRefunds() public onlyOwner {
        isRefundAllowed = !isRefundAllowed;
    }

    // Sends ordered tokens to investors after ICO end if soft cap is reached
    // tokens can be send only if ico has ended
    function sendOrderedTokens() public onlyOwner crowdsaleEnded {
        address investor;
        uint tokensCount;
        for(uint i = 0; i < investors_number.length; i++) {
            investor = investors_number[i];
            tokensCount = orderedTokens[investor];
            assert(tokensCount > 0);
            orderedTokens[investor] = 0;
            token.transfer(investor, tokensCount);
        }
    }

    // Owner can send back collected ETH if soft cap is not reached or KYC is not passed
    // WARNING: crowdsale contract should have all received funds to return them.
    // If you have already withdrawn them, send them back to crowdsale contract
    function refundInvestors() public onlyOwner {
        require(now >= icoEndTime);
        require(isRefundAllowed);
        require(msg.sender.balance > 0);

        address investor;
        uint contributedWei;
        uint tokens;
        for(uint i = 0; i < investors_number.length; i++) {
            investor = investors_number[i];
            contributedWei = contributors[investor];
            tokens = orderedTokens[investor];
            if(contributedWei > 0) {
                totalWeiRaised = totalWeiRaised.sub(contributedWei);
                weiRaised = weiRaised.sub(contributedWei);
                if(weiRaised<0){
                  weiRaised = 0;
                }
                contributors[investor] = 0;
                orderedTokens[investor] = 0;
                tokensDistributed = tokensDistributed.sub(tokens);
                investor.transfer(contributedWei); // return funds back to contributor
            }
        }
    }

    // Owner of contract can withdraw collected ETH by calling this function
    function withdraw() public onlyOwner {
        uint to_send = weiRaised;
        weiRaised = 0;
        FundsWithdrawn(msg.sender, to_send);
        wallet.transfer(to_send);
    }

    function burnUnsold() public onlyOwner crowdsaleEnded {
        uint tokensLeft = totalSupply.sub(tokensDistributed);
        token.burn(tokensLeft);
    }

    function finishIco() public onlyOwner {
        icoEndTime = now;
        foundersTokensUnlockTime = icoEndTime.add(180 days);
    }

    function finishPresale() public onlyOwner {
        presaleEndTime = now;
    }

    function distributeForFoundersAndTeam() public onlyOwner foundersTokensUnlocked {
        uint to_send = 25000000E18; //25m
        checkAndMint(to_send);
        token.transfer(wallet, to_send);
    }

    function distributeForBountiesAndAdvisors() public onlyOwner {
        uint to_send = 15000000E18; //15m
        checkAndMint(to_send);
        token.transfer(wallet, to_send);
    }

    // Used to delay start of ICO
    function updateIcoStartTime(uint _startTime) public onlyOwner {
      require (
        icoStartTime > now &&
        _startTime > now &&
        presaleEndTime < _startTime
      );

      icoStartTime = _startTime;
      setIcoEndTime();
    }

    // After pre-sale made need to reduced hard cap depending on tokens sold
    function updateHardCap(uint _newHardCap) public onlyOwner hardCapNotReached {
        require (
          _newHardCap < hardCap
        );

        hardCap = _newHardCap;
    }

    function transferOwnershipToken(address _to) public onlyOwner {
        token.transferOwnership(_to);
    }

    /***************************
    **  Internal functions    **
    ***************************/

    // Calculates purchase conditions and token bonuses
    function calculatePurchaseAndBonuses(address _beneficiary, uint _weiAmount) internal {
        if (now >= icoStartTime && now < icoEndTime) require(_weiAmount >= icoMinPurchase);

        uint cleanWei; // amount of wei to use for purchase excluding change and hardcap overflows
        uint change;
        uint _tokens;

        //check for hardcap overflow
        if (_weiAmount.add(totalWeiRaised) > hardCap) {
            cleanWei = hardCap.sub(totalWeiRaised);
            change = _weiAmount.sub(cleanWei);
        }
        else cleanWei = _weiAmount;

        assert(cleanWei > 4); // 4 wei is a price of minimal fracture of token

        _tokens = cleanWei.div(rate).mul(1 ether);

        if (contributors[_beneficiary] == 0) investors_number.push(_beneficiary);

        _tokens = calculateBonus(_tokens);
        checkAndMint(_tokens);

        contributors[_beneficiary] = contributors[_beneficiary].add(cleanWei);
        weiRaised = weiRaised.add(cleanWei);
        totalWeiRaised = totalWeiRaised.add(cleanWei);
        tokensDistributed = tokensDistributed.add(_tokens);
        orderedTokens[_beneficiary] = orderedTokens[_beneficiary].add(_tokens);

        if (change > 0) _beneficiary.transfer(change);
    }

    // Calculates bonuses based on current stage
    function calculateBonus(uint _baseAmount) internal returns (uint) {
        require(_baseAmount > 0);

        if (now >= presaleStartTime && now < presaleEndTime) {
            return _baseAmount.mul(presaleBonus).div(100);
        }
        else return _baseAmount;
    }

    // Checks if more tokens should be minted based on amount of sold tokens, required additional tokens and total supply.
    // If there are not enough tokens, mint missing tokens
    function checkAndMint(uint _amount) internal {
        uint required = tokensDistributed.add(_amount);
        if(required > totalSupply) token.mint(this, required.sub(totalSupply));
    }
}
