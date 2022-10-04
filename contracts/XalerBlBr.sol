// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts@4.7.3/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts@4.7.3/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts@4.7.3/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts@4.7.3/access/Ownable.sol";
import "@openzeppelin/contracts@4.7.3/utils/Counters.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "hardhat/console.sol";

contract XalerBlBr is ERC721, ERC721Enumerable, ERC721URIStorage, Ownable, KeeperCompatibleInterface, VRFConsumerBaseV2 {
  // VRFCoordinatorV2Interface COORDINATOR;
    using Counters for Counters.Counter;
      
    Counters.Counter private _tokenIdCounter;
    uint public /*inmutable*/ interval;
    uint public lastTimeStamp;
    
    AggregatorV3Interface public priceFeed;
    int256 public currentPrice;

    VRFCoordinatorV2Interface public COORDINATOR;
    uint256[] public s_randomWords;
    uint256 public s_requestId;
    uint32 public callbackGasLimit = 2500000; // set higher as fulfillRandomWords is doing a LOT of heavy lifting.
    uint64 public s_subscriptionId;
    bytes32 keyhash =  0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f; // keyhash, see for Mumbai https://docs.chain.link/docs/vrf-contracts/#rinkeby-testnet
    
    enum MarketTrend{BULL, BEAR} // Create Enum
    MarketTrend public currentMarketTrend = MarketTrend.BULL; 

    string [] bullUriIpfs = [
        "https://ipfs.io/ipfs/QmR5VGx8mZEE3p7CH35EeGfm3UrDz6KJHU77WvCLk5ZG8e?filename=gamer_bull.json",
        "https://ipfs.io/ipfs/QmacvyW6N2mzJkvXwTW3f6QXMdvFRA5UqByd6xLmJSRiGU?filename=party_bull.json",
        "https://ipfs.io/ipfs/QmVroKHHgpnuFSBBT8jqZmVjgefqgGQ5aaTmrsNEZnZsNV?filename=simple_bull.json"
    ];

    string [] bearUriIpfs = [
        "https://ipfs.io/ipfs/Qmb7cEJWjWf6QH5DNkBxSmazgWsxodrC31v5aoTH5h9kiK?filename=beanie_bear.json",
        "https://ipfs.io/ipfs/QmX4chXrrPbhH9z7EZ7A8v22r3QUGcdGRuLb6vYxT4rD7R?filename=coolio_bear.json",
        "https://ipfs.io/ipfs/QmYLpUy7nYMAGuJPh23JnUgivYRBqPZu1dubqjWDGEoKWm?filename=simple_bear.json"
    ];

    event TokensUpdated(string marketTrend);

    constructor(uint updateInterval, address _priceFeed,  address _vrfCoordinator) ERC721("XalerBlBr", "XLRBB") VRFConsumerBaseV2(_vrfCoordinator){
        //Sets  the keeper update interval
        interval = updateInterval;
        lastTimeStamp = block.timestamp;

        //Set the price feed to
        // For testing with the mock on Mumbai, pass in 10(seconds) for `updateInterval` and the address of your 
        // deployed  MockPriceFeed.sol contract.
        //BTC/USD  Price feed Contract Adrress on Mumbai: https://mumbai.polygonscan.com/address/0x007A22900a3B98143368Bd5906f8E17e9867581b
        // Setup VRF. Mumbai VRF Coordinator 0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed

        priceFeed = AggregatorV3Interface(_priceFeed);

        currentPrice = getLatestPrice();
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);  
    }

    function safeMint(address to) public onlyOwner {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        //Default to gamer bull NFT image
        //string memory defaultUri = bullUriIpfs[randomness(3,1)];
        string memory defaultUri = bullUriIpfs[0];
        _setTokenURI(tokenId, defaultUri);

         console.log("DONE!!! minted token ", tokenId, " and assigned token url: ", defaultUri);
    }

    function checkUpkeep (bytes calldata /*checkdata*/) external view override returns (bool upkeepNeeded, bytes memory /*performData*/){
        upkeepNeeded = (block.timestamp - lastTimeStamp) > interval;
    }

    function performUpkeep (bytes calldata /*performData*/) external override {
        if((block.timestamp - lastTimeStamp) > interval){
            lastTimeStamp = block.timestamp;

            int latestPrice = getLatestPrice();

            if(latestPrice == currentPrice){
                console.log("NO CHANGE -> returning!");
                return;
            }
            if(latestPrice < currentPrice){
                //bear
                //updateAllTokenUris("bear");
                currentMarketTrend = MarketTrend.BEAR;
            }else{
                //bull
                //updateAllTokenUris("bull");
                currentMarketTrend = MarketTrend.BULL;
            }
            requestRandomnessForNFTUris();
            currentPrice = latestPrice;
        }else {
            console.log(" INTERVAL NOT UP!");
            //interval not elapsed. No upkeep
        }
    }

    function getLatestPrice () public view  returns (int256) {
       (
           /*uint80 RoundID*/,
           int Price,
           /*uint startedAt*/,
           /*uint timeStamp*/,
           /*uint80 answeredInRound*/           
       ) = priceFeed.latestRoundData();
       //example price returned 302010102030 
       return Price;
    }

    function requestRandomnessForNFTUris() internal {
        require(s_subscriptionId != 0, "Subscription ID not set"); 

        // Will revert if subscription is not set and funded.
        s_requestId = COORDINATOR.requestRandomWords(
            keyhash,
            s_subscriptionId, // 2019
            3, //minimum confirmations before response
            callbackGasLimit,
            1 // `numWords` : number of random values we want.
        );

        console.log("Request ID: ", s_requestId);
    }

     // This is the callback that the VRF coordinator sends the 
    // random values to.
    function fulfillRandomWords(
        uint256, /* requestId */
        uint256[] memory randomWords
    ) internal override {
        s_randomWords = randomWords;
        // randomWords looks like this uint256: 68187645017388103597074813724954069904348581739269924188458647203960383435815

        console.log("...Fulfilling random Words");

        string[] memory urisForTrend = currentMarketTrend == MarketTrend.BULL ? bullUriIpfs : bearUriIpfs;
        uint256 idx = randomWords[0] % urisForTrend.length; // use modulo to choose a random index.


        for (uint i = 0; i < _tokenIdCounter.current() ; i++) {
            _setTokenURI(i, urisForTrend[idx]);
        } 

        string memory trend = currentMarketTrend == MarketTrend.BULL ? "bullish" : "bearish";
        
        emit TokensUpdated(trend);
    }

    function setInterval(uint256 newInterval) public onlyOwner{
        interval = newInterval;
    }

    function setPriceFeed(address newFeed) public onlyOwner{
        priceFeed = AggregatorV3Interface(newFeed);
    }

     // For VRF Subscription Manager
    function setSubscriptionId(uint64 _id) public onlyOwner {
        s_subscriptionId = _id;
    }


    function setCallbackGasLimit(uint32 maxGas) public onlyOwner {
        callbackGasLimit = maxGas;
    }

    function setVrfCoodinator(address _address) public onlyOwner {
        COORDINATOR = VRFCoordinatorV2Interface(_address);
    }


    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public view override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
