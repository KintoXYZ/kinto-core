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
        bool mint;
    }

    Record[] public records;

    function run() public override {
        super.run();

        BridgedKinto kintoToken = BridgedKinto(_getChainDeployment("KINTO"));

        // ────────────────────── hack-cleanup records ──────────────────────
        records.push(
            Record({user: 0x9F04796758aFB36C2b028BD6a41C7DcF3c19d52e, shares: 46647003430218700000, mint: true})
        );
        records.push(
            Record({user: 0x793500709506652Fcc61F0d2D0fDa605638D4293, shares: 110058943328591000000, mint: false})
        );
        records.push(
            Record({user: 0x3De040ef2Fbf9158BADF559C5606d7706ca72309, shares: 20899709124338600000000, mint: true})
        );
        records.push(
            Record({user: 0x66007079aCbebB3Fb5261B4ED0818f4c0542Aa5A, shares: 88863899999999900000, mint: false})
        );
        records.push(Record({user: 0x342edAAe07B11d7542C2e82BaE6BBf17804B0fCA, shares: 999942223853954000, mint: true}));
        records.push(
            Record({user: 0xD157904639E89df05e89e0DabeEC99aE3d74F9AA, shares: 1147709861557460000000, mint: true})
        );
        records.push(
            Record({user: 0x9d964B38B01E158dc1B059D4FFC681dca12004fb, shares: 41742880168311300000, mint: true})
        );
        records.push(
            Record({user: 0x2e5b575BB803324d616f761FEEA0C19C03B6F77d, shares: 413330842262962000, mint: false})
        );
        records.push(
            Record({user: 0xFc7647485CEee6c482E1fecDb4ab36fe390780d8, shares: 117863153050638000, mint: false})
        );
        records.push(
            Record({user: 0x34d8BaD8b1e84287f9a99FD0162787C065F2422d, shares: 15504579501513800000, mint: false})
        );
        records.push(Record({user: 0xbd08200C3BD228118a9dBC7301Db93f71fCb96E5, shares: 44695479803904, mint: true}));
        records.push(
            Record({user: 0x5A1e00984Af33BED5520Fd13e9c940F9f913cF10, shares: 8153784200050000000000, mint: false})
        );
        records.push(
            Record({user: 0xC3ffD33d56FdB24C8E1e9f6B27220Ef906c851e9, shares: 41861101957132600000, mint: false})
        );
        records.push(
            Record({user: 0x560FfE35Ad1a41BDFD4f1A54AC43B6FE1Ff30458, shares: 9078966286582070000, mint: false})
        );
        records.push(
            Record({user: 0xc8F59918bf67d2B18BBFC3BB3C1F2183AB1840cc, shares: 20479100000000000000, mint: true})
        );
        records.push(Record({user: 0xa8a0cb4E2DBbeC8057e69B1d4D69E5cF74EAc819, shares: 43147789808300000, mint: true}));
        records.push(
            Record({user: 0x1d66b926A66594AD8CD613da6AF5Cc1C3C5863af, shares: 111904040019078000000, mint: false})
        );
        records.push(Record({user: 0x9f8a815A85a31464Ec879c9D3f03fF5883D723A1, shares: 995436450355468000, mint: true}));
        records.push(
            Record({user: 0x1c95Ab93F8971CC774B27c39ee3561FA335bDdEe, shares: 24839406049083600000, mint: false})
        );
        records.push(
            Record({user: 0xd3394a73f636a22F73FED5eb2B3E18F7e97Bb036, shares: 3022551141642340000, mint: false})
        );
        records.push(
            Record({user: 0xCAc1c83543d583A195ba976e5227C39C0719069e, shares: 93936813024940100000, mint: true})
        );
        records.push(
            Record({user: 0xbe7f605ebF7a360Dd91fD759e80404C20FdB669E, shares: 203095862722495000000, mint: true})
        );
        records.push(
            Record({user: 0x503799C5b9b49fdB0da3dc2AFEa1248295eD67b6, shares: 280600202718396000, mint: false})
        );
        records.push(
            Record({user: 0x850eD89D921fd18A4870bbE5ae889932e6c8fFaf, shares: 2303866666666800000, mint: true})
        );
        records.push(
            Record({user: 0xFdB3a148993974ED5156EC653477F7334D605845, shares: 89498574278829200000, mint: false})
        );
        records.push(Record({user: 0xd17f5723742E43222b3A26d1ad2536a1AE0108fC, shares: 234007749005081000, mint: true}));
        records.push(
            Record({user: 0x0d8636bd068Fe6Aee2B3ea20e98255ADD33Ec208, shares: 26051175457840700000, mint: true})
        );
        records.push(
            Record({user: 0xf59E927E4cF3d84acb808b3B8de6be7F2c67f215, shares: 2491038020389990000, mint: true})
        );
        records.push(
            Record({user: 0x2f451B592F232b5e875012c36bbA4bad166473be, shares: 61001102825825500000, mint: true})
        );
        records.push(
            Record({user: 0xD5d7540cCef6c99BE67486AC2b8d317FfC6544EA, shares: 25181931212161900000, mint: false})
        );
        records.push(
            Record({user: 0x6F837C207925400F246BcA336Eb64e0eD21EdCc2, shares: 64056467544122200000, mint: false})
        );
        records.push(
            Record({user: 0x2b9798745734E81C3060871045F8c7a3c8Eb2caB, shares: 85194378095392800000, mint: false})
        );
        records.push(
            Record({user: 0x49fD56971Ad196268FB26d9a46D6E2F3efA9ee9e, shares: 887089339085234000, mint: false})
        );
        records.push(
            Record({user: 0x9F86444Cf2964403A3fA616385917a420FD4726C, shares: 17090866100367000000, mint: false})
        );
        records.push(
            Record({user: 0x7630cc5D76D92c2B678B8C94b015F1c0D3bB5022, shares: 3485540134782760000, mint: false})
        );
        records.push(Record({user: 0xA830D59962aebdF551A12ce2f53CeE2f6E731c86, shares: 448033258007036000, mint: true}));
        records.push(
            Record({user: 0x8a0eebE9BE754Eb13d8cF93d1B728D78865577EA, shares: 261632865308237000000, mint: false})
        );
        records.push(
            Record({user: 0xCd176d0e48e000B4e9CA475f277584FaA2DE5195, shares: 17586636277393000000, mint: true})
        );
        records.push(
            Record({user: 0x6C03a3A6a49C6e7262759aC20774Fa1446883A32, shares: 34098390243639500000, mint: false})
        );
        records.push(
            Record({user: 0xe5015b6380E8F0b8Eea39D9292eFd33686eBBc9A, shares: 936901932768206000, mint: false})
        );
        records.push(Record({user: 0x6bb4c01cc2430875751A5ddE0A466D987c0F1365, shares: 19035851198464, mint: false}));
        records.push(
            Record({user: 0x2D33caf07d0396b73635C232222b4105e2d60c61, shares: 53308084036047500000, mint: false})
        );
        records.push(
            Record({user: 0x88Db47D58Abe4A27619e59F211765AD53c813714, shares: 21752752504447800000, mint: false})
        );
        records.push(Record({user: 0x38FE78B464761B99402D29Bb9c86568E9e6DF7E5, shares: 177289741760201000, mint: true}));
        records.push(
            Record({user: 0x27F2eACc011ecA4165eb7d44815238A03DC768b5, shares: 37158000000000000000, mint: true})
        );
        records.push(
            Record({user: 0x483e3583854E9A16d3412AE3cC3102cDbF2A7D15, shares: 25335005543405100000, mint: false})
        );
        records.push(
            Record({user: 0x4DF40270546514A7bb21F4C4ec269B3c549ac9A6, shares: 805781798222635000000, mint: false})
        );
        records.push(Record({user: 0x7534657ADac296FCfBE16BD08AF258E33BEe017A, shares: 92419923800064, mint: true}));
        records.push(
            Record({user: 0xC8dC1327ae81062AEBB1E301042d9AB3394B4149, shares: 38366879508400800000, mint: false})
        );
        records.push(
            Record({user: 0x3934D981a66E4BFD0F82EF99C9F405767f1cCfBD, shares: 87043056745804700000, mint: false})
        );
        records.push(
            Record({user: 0xf4a5e3B0f44D292774D2E35D55439940dFD62bC5, shares: 402258604541016000, mint: false})
        );
        records.push(
            Record({user: 0xd41feF730f89ae5D4A7bcB3AF0A92B2adB7FD058, shares: 33386802240389700000, mint: true})
        );
        records.push(
            Record({user: 0xABbc5Fa34FBC91B77c3306BEDB94e25404dbeADc, shares: 60040463095458200000, mint: false})
        );
        records.push(
            Record({user: 0x2B5650e8BD12F1df5ac15c3613949dC4Df6E8735, shares: 10024637349413900000, mint: true})
        );
        records.push(
            Record({user: 0x871BCf82A2dd8c427441E0FE60fcbe56022DF446, shares: 9232460397819780000, mint: true})
        );
        records.push(Record({user: 0xeead23E83AC9139ec420b1083467fa05EDE5616E, shares: 488413354571006000, mint: true}));
        records.push(Record({user: 0x694AD53083DE3142Dd790DA2Fd66ADC5aAD9ECF7, shares: 15657219391488, mint: false}));
        records.push(
            Record({user: 0x3779679695bF963A24F10D5B17B34D5E8cCFf9C6, shares: 2703005900000000000000, mint: false})
        );
        records.push(
            Record({user: 0x21d3e325a7B9D21F0753E558A05b51b011807218, shares: 31420200000000000000, mint: true})
        );
        records.push(Record({user: 0xf80B444FeC79cC4f8F6f7D03505355f252dD1865, shares: 368222414278500000, mint: true}));
        records.push(
            Record({user: 0x0A6d6a9f95E68f0aB78eB081b5b21760CCC67356, shares: 21859754108926000000, mint: true})
        );
        records.push(
            Record({user: 0xc4891f47f596516213152E7C1cdC1179BccBeABb, shares: 683960000000000000000, mint: false})
        );
        records.push(
            Record({user: 0xE2d3C5c99994C16FAf4e1fDf1fC23CA4cfC1Ef42, shares: 24441966382583400000, mint: false})
        );
        records.push(
            Record({user: 0xb8310d4fa4460ec008FfFbe459451B848174e9F5, shares: 83616666666666500000, mint: false})
        );
        records.push(
            Record({user: 0xE6b5CfE8AD719a36d2b5F4d9B036bb8b8288532F, shares: 61573825757580300000, mint: false})
        );
        records.push(
            Record({user: 0x197Dc1B6723df7AeDeF7bB8198398D652CA322f0, shares: 8333333333333230000, mint: false})
        );
        records.push(
            Record({user: 0x1af08CFEA525667c975223A8c298e60a43e96A67, shares: 164066728792334000, mint: false})
        );
        records.push(
            Record({user: 0x864990EEc44952Ac4245614f448aDBcE2bdb5028, shares: 442715769662054000000, mint: false})
        );
        records.push(
            Record({user: 0x7e6071bb0E16B1FB28e1957b861B26117E56cC3F, shares: 3653186742372050000000, mint: false})
        );
        records.push(
            Record({user: 0xce039F8Db681515D90aBBd6C51cb012Ca0783766, shares: 154862080719199000, mint: false})
        );
        records.push(
            Record({user: 0xE3343d959B5a2c3Dcd94a50cD71135A3e9fEFc5F, shares: 724538335217401000, mint: false})
        );
        records.push(
            Record({user: 0x8cad29e294f0b7c2844462E8344E0629E2d5b108, shares: 37157930411107000000, mint: false})
        );
        records.push(
            Record({user: 0xf8719f51d7Cc5738A7E1e0eD0974a60e708f67Ea, shares: 36921624826921800000, mint: false})
        );
        records.push(
            Record({user: 0xFd9F3a0eac7f06ddD8f579B9CFfdF6dEF86da3a9, shares: 431707512661174000000, mint: false})
        );
        records.push(Record({user: 0x3147DC52fa246f1C424C97fBA69e5cc0a8c5EA53, shares: 100000000114688, mint: false}));
        records.push(
            Record({user: 0x99918c6454945819D60182Fcadd07319818D5e61, shares: 778501194176593000, mint: false})
        );
        records.push(
            Record({user: 0x9EeA9C32196F4A03a03B173803a72f43b3Fe31E0, shares: 1727605628250100000, mint: true})
        );
        records.push(
            Record({user: 0x5bb5B8bD531c8FC555Cc40cFF9a65F694Ed87048, shares: 21462392892460700000, mint: true})
        );
        records.push(
            Record({user: 0x974E38164B58f344098E865E981d8a33697FFB32, shares: 4826734850773200000, mint: false})
        );
        records.push(
            Record({user: 0x05A4122b85a62540A5195C2577B993bC23228d06, shares: 7503361630830070000, mint: true})
        );
        records.push(
            Record({user: 0x04EFE7Fd10CD546d30fAf75475c1275b9D15DBc6, shares: 84610498512526200000, mint: false})
        );
        records.push(
            Record({user: 0xd892d8FCA88EF30E15f5D201F08E8C79CF009c37, shares: 133629630815297000, mint: false})
        );
        records.push(
            Record({user: 0x9659141F26fc8e6f8A54fb1704Cb3370EB60fea0, shares: 370190600000000000000, mint: false})
        );
        records.push(
            Record({user: 0x911b291a67B62d4358199AF36B94f4BBAB43c2eE, shares: 160455799912271000000, mint: false})
        );
        records.push(Record({user: 0x250D3D4Dd20B1817e52841B46cD4D48f6B4bCEea, shares: 9417764446994430, mint: true}));
        records.push(
            Record({user: 0x893a246066bd976e44d6d00684dec07C52Baa492, shares: 49884088457746200000, mint: false})
        );
        records.push(Record({user: 0x62e463CC8F5c7e8234d785839274143513a0A0b6, shares: 696615157778575000, mint: true}));
        records.push(Record({user: 0x6A5E1c3CCd58D0a6064C9229DaD012553d5BAe2C, shares: 15500000000000000, mint: true}));
        records.push(
            Record({user: 0x041331231C6727403ADA5AeE33b8988D5063fC76, shares: 199999900000000000000, mint: true})
        );
        records.push(
            Record({user: 0x0B475E5f6ef7B2f840fF43d8d564205A1e5eD84A, shares: 32337004302836000000, mint: false})
        );
        records.push(
            Record({user: 0x29725FEA0e3826B3c1B67599954108a4921697fd, shares: 190505880200574000000, mint: false})
        );
        records.push(
            Record({user: 0xF514265CB9535B8dFf64dc838f68A6EF64Aa7cD8, shares: 76501412148345000000, mint: false})
        );
        records.push(
            Record({user: 0x8e926c278acF7d63D223f090e68Bff402bfa568c, shares: 69631542352116100000, mint: false})
        );
        records.push(
            Record({user: 0xdAa4dABEC8626C537F59a6073bD35FB0A1290350, shares: 148966501980341000000, mint: false})
        );
        records.push(
            Record({user: 0x55B8be0d6D325Ab09AFd0dbfE3D5F420024d1095, shares: 437028527970973000, mint: false})
        );
        records.push(
            Record({user: 0xD0062EA9d10f3Fe266A8cD821C8F4d29299C38ae, shares: 52860100000000000000, mint: true})
        );
        records.push(
            Record({user: 0x0Fe7f34d2460e2D9d64c5D75Fed755Eb3d0d6f63, shares: 163361011176980000, mint: false})
        );
        records.push(
            Record({user: 0x31B2Dda4b9B16D092aF34b684d6b0cb2eb5f3BB5, shares: 1237028836180000000, mint: true})
        );
        records.push(
            Record({user: 0xdeB6d1D8B199Ce89C520100BA2bE493eE45Ba41c, shares: 176766026335590000000, mint: false})
        );
        records.push(
            Record({user: 0xC2f77a505545798ED01c9304fa5A0abD4799F24A, shares: 253820792986617000000, mint: true})
        );
        records.push(
            Record({user: 0x466fb52d38e9Db3029790AD664A084C2F0f9c30c, shares: 27985727385183300000, mint: true})
        );
        records.push(
            Record({user: 0xF3D78a8A457622F5016AC74EB1F37f3DA09e86Ad, shares: 9536557904332310000, mint: false})
        );
        records.push(
            Record({user: 0x92757E7bc04CC00baF904657AD4a7e2f507569cB, shares: 1531645646167010000, mint: false})
        );
        records.push(
            Record({user: 0x85D3Ad1a246d697871eba1785724004c8AD94a5b, shares: 22116779864962900000, mint: false})
        );
        records.push(Record({user: 0x446238D47CB5BbF2897a243c1D328130F6278E2c, shares: 999971252904804000, mint: true}));
        records.push(Record({user: 0x74E6A4a4Eca5b022B3B626db2dBdE29bEE45E69A, shares: 999966912065576000, mint: true}));
        records.push(
            Record({user: 0x37d3c13a6F09a828Cbf16C724BD129BdB868E6BE, shares: 8428972658403220000, mint: false})
        );
        records.push(
            Record({user: 0x9908f0eA297aE7A1211D0Dbf4f6fA6da737Ddfb4, shares: 340372557632357000, mint: false})
        );
        records.push(
            Record({user: 0xD014ba010A8ABbf75142DE92D155F9911d1AE598, shares: 390414463543388000000, mint: false})
        );
        records.push(
            Record({user: 0x938E3c7F7A610d97bb198aF770fB1600CcdA13D1, shares: 1433402139832930000, mint: true})
        );
        records.push(
            Record({user: 0x69093227605061D43e44dC3852153DE1383aB2A9, shares: 11840169745484300000, mint: false})
        );
        records.push(
            Record({user: 0x64DbbCdc891B91A022ca7e5F35F8D5A0B84ABECd, shares: 646604139899082000, mint: false})
        );
        records.push(
            Record({user: 0x9ba6A569eB6c92Dfe30f90c0FF8EbD13FF316848, shares: 1629170820034990000, mint: true})
        );
        records.push(
            Record({user: 0x6e9D20879C82184AEc9f3191596EEf6708ab9422, shares: 44037409897728900000, mint: true})
        );
        records.push(
            Record({user: 0x15483BAfB9E57C2778E456886617f86f6aDdA1c1, shares: 358331467014328000000, mint: false})
        );
        records.push(
            Record({user: 0x24eC8285Ed0B8373B2eC753CbB668bCbB773d8Ab, shares: 506640500000000000000, mint: true})
        );
        records.push(
            Record({user: 0xda6f319fDaC0b5cddB33F65d41767B200Cb1702e, shares: 377766199800402000, mint: false})
        );
        records.push(Record({user: 0xaF7E6463a5317ACC76De24cDC32DD1896825e768, shares: 46357837004800, mint: true}));
        records.push(
            Record({user: 0x1C4365fe78c03574154d53eeF706c2292146D080, shares: 355857115580637000, mint: false})
        );
        records.push(
            Record({user: 0x754F28780983b11612E8d5D82FB640D884BfF5aE, shares: 6796006349802530000, mint: false})
        );
        records.push(
            Record({user: 0x336F85B5cCC5B48fb83adC143b1Bbde08E17F3aE, shares: 34195816953660400000, mint: false})
        );
        records.push(
            Record({user: 0x55fdb289f71bdf870661f11eE2DD17d8B418803C, shares: 570762190046971000, mint: false})
        );
        records.push(Record({user: 0x548719fBA49B4aF6ea1FB5AB7e806A934E408f5E, shares: 53002742497280, mint: true}));
        records.push(
            Record({user: 0xcCa895Ddc9B2cA904De48437937d3f5653D705c6, shares: 2248122525188240000, mint: false})
        );
        records.push(
            Record({user: 0xc969fA59541c6200Eb73E425354fC008697a0351, shares: 588618822422739000, mint: false})
        );
        records.push(
            Record({user: 0xB3021000B1713de5cD715E22C44A61FeeF853BD9, shares: 1454734074337060000, mint: false})
        );
        records.push(
            Record({user: 0x5b7D41e6bbba99ABC14172dD51F7De94c5c2a961, shares: 9031808608148290000, mint: false})
        );
        records.push(Record({user: 0x01f289df03f61181BC505C34F39801b6F0CC29f8, shares: 474899747346061000, mint: true}));
        records.push(
            Record({user: 0xF005f6620E794279244A7110feE736ED3B1C7F61, shares: 1896586796896910000, mint: false})
        );
        records.push(Record({user: 0xe61D3009A18918CfEDD9EC51b48e0468a12003d5, shares: 36791991992320, mint: false}));
        records.push(
            Record({user: 0x25A6Ca3cED2463E486e49f2EFD2F611D5E725f2d, shares: 1522748959143300000, mint: false})
        );
        records.push(Record({user: 0x2a459d76D7Eeb299D939E17a295D6016F53b8f93, shares: 69942164979712, mint: true}));
        records.push(
            Record({user: 0x96A4fE77Db189b0F5Bd38bb0797e87eDF5081d8e, shares: 10039999983333200000, mint: false})
        );
        records.push(
            Record({user: 0x6D987766D1c268694c88D243D0B7a34107A28577, shares: 3494269515189980000, mint: true})
        );
        records.push(
            Record({user: 0xdBadC4e7fF8f17ddf567bbCfe38c71b0625137E9, shares: 6158535594367380000, mint: true})
        );
        records.push(
            Record({user: 0xC4427A885a8d992CB507a81c3B694744262De62A, shares: 2504030829205990000, mint: false})
        );
        records.push(
            Record({user: 0xb5C22515C09D5161Ceb06Dfdc3f3FA06Eb01aDbd, shares: 45981825111574100000, mint: true})
        );
        records.push(
            Record({user: 0xc385a98D1Bf4B2A2fe523A88b49093cf631f5Ef7, shares: 171550000000000000000, mint: false})
        );
        records.push(
            Record({user: 0x2fd8175c7a3f0FD624859fD55c52f6EC8B58B367, shares: 78736400000000000000, mint: false})
        );
        records.push(Record({user: 0xc8477Ae5eDD9DC7De588A46F47EE0c391e59B600, shares: 9900000000000000, mint: false}));
        records.push(
            Record({user: 0x3Daee3e4BbA14dC32265bEbCeE32Be963CA27e04, shares: 55946709210932900000, mint: false})
        );
        records.push(
            Record({user: 0x18dcc661bFEed31fc433900d5c09f25899f25805, shares: 125882644928931000, mint: false})
        );
        records.push(
            Record({user: 0x5f8C8660580e04B48594963D6BdeB0EB85028B43, shares: 44919300000000000000, mint: false})
        );
        records.push(
            Record({user: 0x7D3F7cbC7208fEFF530f0A075Ab89B0bE2e25e82, shares: 1063909900000000000000, mint: false})
        );
        records.push(
            Record({user: 0x03d35C5Ed389a3feA9Af8921C1B514c60B44e2c2, shares: 34733300000000000000, mint: true})
        );
        records.push(
            Record({user: 0xAE7435C19f2458b066C03fd4C6be35f4De922521, shares: 1216477660477860000, mint: false})
        );
        records.push(
            Record({user: 0xad79d2946160aae406fBa0c1d9D598A735335374, shares: 29450000000000000000, mint: false})
        );
        records.push(
            Record({user: 0x1dB3C1376f99FDcC5B4c830776a2A56427599B71, shares: 121261747201999000, mint: false})
        );
        records.push(
            Record({user: 0xFa4a38B74c258Ab7469bf04AB41bA25910491F6F, shares: 539393452540971000, mint: false})
        );
        records.push(
            Record({user: 0x25499ce734F62cf5Fc8301999185d4A943297B6D, shares: 38179999999999900000, mint: false})
        );
        records.push(
            Record({user: 0x6b7d8C7682cc336DfE26CC3e5042459193808bec, shares: 12358600000000000000, mint: true})
        );
        records.push(
            Record({user: 0x3dFf091f993BC44F96D304243b6CD05D93B26B62, shares: 1210749128446640000, mint: false})
        );
        records.push(
            Record({user: 0x717243C43874D7fbBC6D7F343B977E8A08E8Ab74, shares: 438250747191611000, mint: false})
        );
        records.push(
            Record({user: 0xD8511CedBf108a50fDf429A08e55E49356890169, shares: 246617997349796000, mint: false})
        );
        records.push(
            Record({user: 0xa62c037582c28a51e5611303280f3e7352feE8ad, shares: 58689841970363000000, mint: false})
        );
        records.push(
            Record({user: 0xB41F2e4e157bd0279545121944b4fd4E059afe1a, shares: 9240000000000000000, mint: true})
        );
        records.push(
            Record({user: 0x5bF8370897C549Fc746834bcbaf5866c9f09F602, shares: 166893595514830000, mint: false})
        );
        records.push(
            Record({user: 0xe53f1411665efBfbF7397eE6eE16A8A1dc08229C, shares: 1000000000000000000, mint: true})
        );
        records.push(
            Record({user: 0x8e7ee117Bd41Dd5ca6A76f215b3AC6ea040D7DD9, shares: 1056319062603610000, mint: false})
        );
        records.push(
            Record({user: 0xa8317e15999d79640d1e4bB0975Fa77EbD94E671, shares: 1375913642543890000, mint: false})
        );
        records.push(
            Record({user: 0x22b72ea718C11e780aD293113A9C921BBcb3e4E1, shares: 4176166666666560000, mint: false})
        );
        records.push(
            Record({user: 0x93F96A75Cd46Af34121266756EDB99878070701C, shares: 43972880068277600000, mint: false})
        );
        records.push(
            Record({user: 0x2ffF680e91Cc24602429944DD3c0aCFE115d749B, shares: 316101152898777000, mint: false})
        );
        records.push(
            Record({user: 0x98cA1fb488c76337C4aef26eff0A7C9d886F6104, shares: 7915229438823220000, mint: false})
        );
        records.push(
            Record({user: 0x0d12DD469d710A910D053fe6B04cd37875bAa335, shares: 102818536193294000, mint: false})
        );
        records.push(
            Record({user: 0x01B46CE63FAdcde524998d9387c6C2CfE9D9A3cE, shares: 217198086777303000, mint: false})
        );
        records.push(
            Record({user: 0x1fAB6FFaf7bA08f47E8FA7F1e79b1C816beeDDD1, shares: 431426062240738000, mint: false})
        );
        records.push(
            Record({user: 0x272244338D0034d45EB59e56E3cC5bc2B7a9f9Ff, shares: 26622319074194400000, mint: false})
        );
        records.push(
            Record({user: 0x040E5B7Bba58B87283bEA12136717F21a300685e, shares: 20083263593838500000, mint: false})
        );
        records.push(
            Record({user: 0x63FA661C8B1F85DD7B9F66fbdAd4c4fA7FE97e00, shares: 84451853375855200000, mint: false})
        );
        records.push(
            Record({user: 0x57AE483FCC306D8C71E771A4fBC14605BF8347bB, shares: 110641372431033000000, mint: false})
        );
        records.push(
            Record({user: 0xcf1B41b446BE154B1539D251Fb31fb906C186481, shares: 179390508322089000, mint: false})
        );
        records.push(
            Record({user: 0x937120ecB7576BF60C79C2C68Ec32c6b489148fe, shares: 318696317811499000, mint: false})
        );
        records.push(
            Record({user: 0xb0a2B3e4469277bAC8E773Be4CDAE009848fba42, shares: 25333333333333200000, mint: false})
        );
        records.push(
            Record({user: 0xbf54d351e38Da7D755359fabf89e8864FD0377Cb, shares: 26807219865156800000, mint: false})
        );
        records.push(
            Record({user: 0x342cB256218EFf45705F023352b433659c566185, shares: 16666666666666500000, mint: false})
        );
        records.push(
            Record({user: 0xe403173f8DcBA7339b56d940DCD73C5CB29B1526, shares: 10416666666666500000, mint: false})
        );
        records.push(
            Record({user: 0xBabbAb46D33d4C24474B83c484228D3b618b30F0, shares: 22723335905802400000, mint: false})
        );
        records.push(Record({user: 0x37c4408071915c725A96B205E02ec39C2ca5ACC4, shares: 576700000000000000, mint: true}));
        records.push(
            Record({user: 0xb43862CDC00bfEF7cA9e7447A017aF8f230a9BC3, shares: 989965538655539000, mint: false})
        );
        records.push(
            Record({user: 0x36F12Da92c05Ac7e266761999a0FE336c559BeB8, shares: 164724735346401000, mint: false})
        );
        records.push(
            Record({user: 0x7f26E00D5E13d016E1BCfBc680CFaCF7A6744e14, shares: 2485369915723350000, mint: false})
        );
        records.push(
            Record({user: 0x76B2e9A5A3A81F302DBb160e88397175F315BC61, shares: 1544567944380180000, mint: false})
        );
        records.push(
            Record({user: 0xa5c646a304C88051Ca8521D8170520E807A88260, shares: 33747246402644700000, mint: false})
        );
        records.push(
            Record({user: 0xe847c816b99eB3f7f380B1B377c4c446743666d5, shares: 21194499999999900000, mint: false})
        );
        records.push(Record({user: 0xf26fe167A0f1ccd17f493fbD54bB840EDc1d889d, shares: 9975742626999810, mint: true}));
        records.push(
            Record({user: 0xBa9E760Cbbf6eF7368Ef84558219C46a93cBa215, shares: 1000000000000000000, mint: true}));
        records.push(
            Record({user: 0x8DdE2c811EbdC2f6Cb4E6A02E547712CCa1A8577, shares: 95406786482100700000, mint: false})
        );
        records.push(
            Record({user: 0xB604229540Ae0A8286c014AF2E1366cC8f17BCc6, shares: 3276158726176280000, mint: false})
        );
        records.push(
            Record({user: 0xc339F12bF48AFFaDFE35b5501F18d38937c2048E, shares: 673453315084953000, mint: false})
        );
        records.push(
            Record({user: 0x524b17C6ECbCD0230583407980fcd2eD6e3748De, shares: 673209150635440000000, mint: false})
        );
        records.push(
            Record({user: 0x8B04410adC77a3035DabeE06370F939Ec3AcEAEB, shares: 15866741525121800000, mint: false})
        );
        records.push(
            Record({user: 0xa3B1F5f8BD3150Da92B32e853F474067F1E9Fe02, shares: 108296952324158000000, mint: false})
        );
        records.push(
            Record({user: 0x4Feff2C7809f9a91C4016894c66f03D6d0bde2ba, shares: 4872920754140700000, mint: false})
        );
        records.push(
            Record({user: 0xf8746cE669176680A6864B9532D2C875c729fef6, shares: 2380364746620840000, mint: false})
        );
        records.push(
            Record({user: 0xeAFf2cfb01CD4C0b89C46817B7dC9368e857602a, shares: 208475627312268000000, mint: false})
        );

        records.push(
            Record({user: 0x56a66d37f3054c39d65b0D28957B9A17d0afFcD2, shares: 1000000000000000000, mint: false})
        );
        records.push(
            Record({user: 0x0D18c6D0265178580D0f76e05eB8366dE5E540C8, shares: 1309254270674660000, mint: false})
        );
        records.push(
            Record({user: 0xC516bAAa766112E551108E776357E9c8502376a9, shares: 65942153548533600000, mint: false})
        );
        records.push(
            Record({user: 0xFb78B91B9a95087CBc0538c35ac6763900cAdc0F, shares: 188182779258470000, mint: false})
        );
        records.push(
            Record({user: 0x6e0F6424e81e2Fe0e783CFEd34D552b01e921262, shares: 77542494782060200000, mint: false})
        );
        records.push(
            Record({user: 0x8d4908b7595F4645E0Cfed46eaBb25B5e5296Ce5, shares: 37399525068385500000, mint: false})
        );

        uint256 totalMintRecords = 59;
        uint256 totalBurnRecords = records.length - totalMintRecords;
        address[] memory users1 = new address[](totalMintRecords);
        uint256[] memory shares1 = new uint256[](totalMintRecords);
        uint256[] memory balances = new uint256[](records.length);
        uint256 j = 0;
        for (uint256 i = 0; i < records.length; i++) {
            if (records[i].mint) {
                users1[j] = records[i].user;
                shares1[j] = records[i].shares;
                j++;
            }
            balances[i] = kintoToken.balanceOf(records[i].user);
        }
        _handleOps(
            abi.encodeWithSelector(BridgedToken.batchMint.selector, users1, shares1),
            payable(_getChainDeployment("KINTO"))
        );

        j = 0;
        address[] memory users2 = new address[](totalBurnRecords);
        uint256[] memory shares2 = new uint256[](totalBurnRecords);
        for (uint256 i = 0; i < records.length; i++) {
            if (!records[i].mint) {
                users2[j] = records[i].user;
                shares2[j] = records[i].shares;
                j++;
            }
        }

        _handleOps(
            abi.encodeWithSelector(BridgedToken.batchBurn.selector, users2, shares2),
            payable(_getChainDeployment("KINTO"))
        );

        require(kintoToken.balanceOf(records[0].user) == balances[0] + 46647003430218700000, "Did not mint");
        require(kintoToken.balanceOf(records[1].user) == balances[1] - 110058943328591000000, "Did not burn");
        require(
            kintoToken.balanceOf(records[records.length - 1].user)
                == balances[records.length - 1] - 37399525068385500000,
            "Did not burn"
        );
    }
}
