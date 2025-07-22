// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {BridgedToken} from "@kinto-core/tokens/bridged/BridgedToken.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FixKintoPreHack is MigrationHelper {
    using Strings for string;

    struct Record {
        address user;
        uint256 shares;
    }

    Record[] public records;

    function run() public override {
        super.run();

        BridgedKinto kintoToken = BridgedKinto(_getChainDeployment("KINTO"));

        // ────────────────────── post-hack-swap records ──────────────────────
      records.push(Record({user: 0x7e6071bb0E16B1FB28e1957b861B26117E56cC3F, shares: 523549465199999975424}));
      records.push(Record({user: 0x694AD53083DE3142Dd790DA2Fd66ADC5aAD9ECF7, shares: 412938502700000018432}));
      records.push(Record({user: 0xC2f77a505545798ED01c9304fa5A0abD4799F24A, shares: 140106951900000010240}));
      records.push(Record({user: 0x4DF40270546514A7bb21F4C4ec269B3c549ac9A6, shares: 97508021389999996928}));
      records.push(Record({user: 0x0A6d6a9f95E68f0aB78eB081b5b21760CCC67356, shares: 53203208560000000000}));
      records.push(Record({user: 0x1d66b926A66594AD8CD613da6AF5Cc1C3C5863af, shares: 37953208560000000000}));
      records.push(Record({user: 0xFd9F3a0eac7f06ddD8f579B9CFfdF6dEF86da3a9, shares: 33818181819999997952}));
      records.push(Record({user: 0x9ba6A569eB6c92Dfe30f90c0FF8EbD13FF316848, shares: 28272727270000001024}));
      records.push(Record({user: 0x864990EEc44952Ac4245614f448aDBcE2bdb5028, shares: 37867647060000006144}));
      records.push(Record({user: 0xD014ba010A8ABbf75142DE92D155F9911d1AE598, shares: 27069518720000000000}));
      records.push(Record({user: 0x29725FEA0e3826B3c1B67599954108a4921697fd, shares: 17382352940000000000}));
      records.push(Record({user: 0xeAFf2cfb01CD4C0b89C46817B7dC9368e857602a, shares: 16692513370000001024}));
      records.push(Record({user: 0xC3ffD33d56FdB24C8E1e9f6B27220Ef906c851e9, shares: 16676470590000001024}));
      records.push(Record({user: 0xe61D3009A18918CfEDD9EC51b48e0468a12003d5, shares: 16041443850000001024}));
      records.push(Record({user: 0x2b9798745734E81C3060871045F8c7a3c8Eb2caB, shares: 13501336900000000000}));
      records.push(Record({user: 0x250D3D4Dd20B1817e52841B46cD4D48f6B4bCEea, shares: 13501336900000000000}));
      records.push(Record({user: 0x8a0eebE9BE754Eb13d8cF93d1B728D78865577EA, shares: 26735294120000002048}));
      records.push(Record({user: 0x3934D981a66E4BFD0F82EF99C9F405767f1cCfBD, shares: 12164438500000000000}));
      records.push(Record({user: 0xdeB6d1D8B199Ce89C520100BA2bE493eE45Ba41c, shares: 16368983960000000000}));
      records.push(Record({user: 0x57AE483FCC306D8C71E771A4fBC14605BF8347bB, shares: 10676470590000001024}));
      records.push(Record({user: 0x15483BAfB9E57C2778E456886617f86f6aDdA1c1, shares: 22834224600000001024}));
      records.push(Record({user: 0x911b291a67B62d4358199AF36B94f4BBAB43c2eE, shares: 13672459890000000000}));
      records.push(Record({user: 0xa3B1F5f8BD3150Da92B32e853F474067F1E9Fe02, shares: 9699197861000000000}));
      records.push(Record({user: 0xFdB3a148993974ED5156EC653477F7334D605845, shares: 10847593580000000000}));
      records.push(Record({user: 0x8cad29e294f0b7c2844462E8344E0629E2d5b108, shares: 8935828877000000000}));
      records.push(Record({user: 0xf59E927E4cF3d84acb808b3B8de6be7F2c67f215, shares: 18743315510000000000}));
      records.push(Record({user: 0xABbc5Fa34FBC91B77c3306BEDB94e25404dbeADc, shares: 7998663102000000000}));
      records.push(Record({user: 0x2D33caf07d0396b73635C232222b4105e2d60c61, shares: 7586898396000000000}));
      records.push(Record({user: 0x8e926c278acF7d63D223f090e68Bff402bfa568c, shares: 7322192513000000000}));
      records.push(Record({user: 0xC516bAAa766112E551108E776357E9c8502376a9, shares: 6788770053000000000}));
      records.push(Record({user: 0xF514265CB9535B8dFf64dc838f68A6EF64Aa7cD8, shares: 6754010695000000000}));
      records.push(Record({user: 0xeead23E83AC9139ec420b1083467fa05EDE5616E, shares: 10307486630000000000}));
      records.push(Record({user: 0xE6b5CfE8AD719a36d2b5F4d9B036bb8b8288532F, shares: 6684491979000000000}));
      records.push(Record({user: 0xaF7E6463a5317ACC76De24cDC32DD1896825e768, shares: 6684491979000000000}));
      records.push(Record({user: 0x6D987766D1c268694c88D243D0B7a34107A28577, shares: 6649732620000000000}));
      records.push(Record({user: 0x6e0F6424e81e2Fe0e783CFEd34D552b01e921262, shares: 6152406417000000000}));
      records.push(Record({user: 0x34d8BaD8b1e84287f9a99FD0162787C065F2422d, shares: 6136363636000000000}));
      records.push(Record({user: 0xC8dC1327ae81062AEBB1E301042d9AB3394B4149, shares: 5347593583000000000}));
      records.push(Record({user: 0x04EFE7Fd10CD546d30fAf75475c1275b9D15DBc6, shares: 5347593583000000000}));
      records.push(Record({user: 0x483e3583854E9A16d3412AE3cC3102cDbF2A7D15, shares: 4875668449000000000}));
      records.push(Record({user: 0x893a246066bd976e44d6d00684dec07C52Baa492, shares: 4855614973000000000}));
      records.push(Record({user: 0xa62c037582c28a51e5611303280f3e7352feE8ad, shares: 4848930481000000000}));
      records.push(Record({user: 0x93F96A75Cd46Af34121266756EDB99878070701C, shares: 4082887701000000000}));
      records.push(Record({user: 0xD5d7540cCef6c99BE67486AC2b8d317FfC6544EA, shares: 3851604278000000000}));
      records.push(Record({user: 0x6bb4c01cc2430875751A5ddE0A466D987c0F1365, shares: 3709291444000000000}));
      records.push(Record({user: 0x8d4908b7595F4645E0Cfed46eaBb25B5e5296Ce5, shares: 3521390374000000000}));
      records.push(Record({user: 0x88Db47D58Abe4A27619e59F211765AD53c813714, shares: 3425133690000000000}));
      records.push(Record({user: 0x3Daee3e4BbA14dC32265bEbCeE32Be963CA27e04, shares: 3364973262000000000}));
      records.push(Record({user: 0x560FfE35Ad1a41BDFD4f1A54AC43B6FE1Ff30458, shares: 3359625668000000000}));
      records.push(Record({user: 0xf8719f51d7Cc5738A7E1e0eD0974a60e708f67Ea, shares: 3342245989000000000}));
      records.push(Record({user: 0x8DdE2c811EbdC2f6Cb4E6A02E547712CCa1A8577, shares: 6549465241000000512}));
      records.push(Record({user: 0x6F837C207925400F246BcA336Eb64e0eD21EdCc2, shares: 3165775401000000000}));
      records.push(Record({user: 0xbf54d351e38Da7D755359fabf89e8864FD0377Cb, shares: 3152406417000000000}));
      records.push(Record({user: 0x548719fBA49B4aF6ea1FB5AB7e806A934E408f5E, shares: 3038770053000000000}));
      records.push(Record({user: 0x0B475E5f6ef7B2f840fF43d8d564205A1e5eD84A, shares: 2844919786000000000}));
      records.push(Record({user: 0x31B2Dda4b9B16D092aF34b684d6b0cb2eb5f3BB5, shares: 2807486631000000000}));
      records.push(Record({user: 0x1c95Ab93F8971CC774B27c39ee3561FA335bDdEe, shares: 4050802139000000000}));
      records.push(Record({user: 0x7534657ADac296FCfBE16BD08AF258E33BEe017A, shares: 2673796791000000000}));
      records.push(Record({user: 0xE2d3C5c99994C16FAf4e1fDf1fC23CA4cfC1Ef42, shares: 2673796791000000000}));
      records.push(Record({user: 0xc8477Ae5eDD9DC7De588A46F47EE0c391e59B600, shares: 1604278075000000000}));


        uint256 totalMintRecords = records.length;
        address[] memory users1 = new address[](totalMintRecords);
        uint256[] memory shares1 = new uint256[](totalMintRecords);
        uint256[] memory balances = new uint256[](records.length);
        uint256 total = 0;
        for (uint256 i = 0; i < records.length; i++) {
            users1[i] = records[i].user;
            shares1[i] = records[i].shares;
            balances[i] = kintoToken.balanceOf(records[i].user);
            total += records[i].shares;
        }

        _handleOps(
            abi.encodeWithSelector(BridgedToken.burn.selector, _getChainDeployment("RewardsDistributor"), total + 3797040),
            payable(_getChainDeployment("KINTO"))
        );

        _handleOps(
            abi.encodeWithSelector(BridgedToken.batchMint.selector, users1, shares1),
            payable(_getChainDeployment("KINTO"))
        );

        require(kintoToken.balanceOf(records[0].user) == balances[0] + 523549465199999975424, "Did not mint");
        require(kintoToken.balanceOf(records[1].user) == balances[1] + 412938502700000018432, "Did not mint");
        require(
            kintoToken.balanceOf(records[records.length - 1].user)
                == balances[records.length - 1] + 1604278075000000000,
            "Did not burn"
        );
        require(total >= 1802e18 && total <= 1803e18, "Total minted");
        console2.log("total", total);

        require(kintoToken.totalSupply() == 10_000_000e18, "Total Supply changed");
    }
}
