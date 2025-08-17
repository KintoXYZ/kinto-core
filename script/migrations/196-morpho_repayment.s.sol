// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MorphoRepayment} from "@kinto-core/vaults/MorphoRepayment.sol";

import {SafeBeaconProxy} from "@kinto-core/proxy/SafeBeaconProxy.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";

import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {
    IERC20Upgradeable,
    IERC20MetadataUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import "@kinto-core-test/helpers/ArrayHelpers.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract DeployScript is Script, MigrationHelper {
    using ArrayHelpers for *;

    struct Record {
        address user;
        uint256 collateralLocked;
        uint256 usdcLent;
        uint256 usdcBorrowed;
    }

    Record[] public records;
    MorphoRepayment.UserInfo[] public infos;

    address public constant SOCKET_APP = 0x3e9727470C66B1e77034590926CDe0242B5A3dCc;
    address public constant K = 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87;
    address public constant USDC = 0x05DC0010C9902EcF6CBc921c6A4bd971c69E5A2E;
    //May 15th, 2025, 10:00:00 AM PT.
    uint256 public constant END_TIME = 1747238400;

    function run() public override {
        super.run();

        if (_getChainDeployment("MorphoRepayment") != address(0)) {
            console2.log("MorphoRepayment is deployed");
            return;
        }

        vm.broadcast(deployerPrivateKey);
        MorphoRepayment impl = new MorphoRepayment(IERC20Upgradeable(K), IERC20Upgradeable(USDC));

        (bytes32 salt, address expectedAddress) =
            mineSalt(keccak256(abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(address(impl), ""))), "5A1E00");

        console2.log("Deployed impl");
        vm.broadcast(deployerPrivateKey);
        UUPSProxy proxy = new UUPSProxy{salt: salt}(address(impl), "");
        MorphoRepayment morphoRepayment = MorphoRepayment(address(proxy));

        console2.log("Deployed proxy");

        _handleOps(
            abi.encodeWithSelector(
                KintoAppRegistry.addAppContracts.selector, SOCKET_APP, [address(morphoRepayment)].toMemoryArray()
            ),
            address(_getChainDeployment("KintoAppRegistry"))
        );

        console2.log("set in pp");

        console2.log("BBBB");
        _handleOps(
            abi.encodeWithSelector(MorphoRepayment.initialize.selector),
            address(proxy)
        );
        console2.log("AAAAAA");

        // Push records
        // Auto-generated records (scaled: USDC x1e6, collateral x1e18)
        records.push(
            Record({
                user: 0x92757E7bc04CC00baF904657AD4a7e2f507569cB,
                collateralLocked: 1000100000000000000,
                usdcLent: 20026062,
                usdcBorrowed: 2002931
            })
        );

        records.push(
            Record({
                user: 0x8379748e7079e8309b955726a7D146d4239ddB28,
                collateralLocked: 0,
                usdcLent: 10013,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x0214D5c5591bd3691d8841D3BBD0f24a9fCdc41F,
                collateralLocked: 0,
                usdcLent: 190247803,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x59C66Bd733e4235814a20fa9E1Ba80eCA70A30c6,
                collateralLocked: 0,
                usdcLent: 3696102959,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x0070e28b14C00fA66DC2abF94d04Cf37C938c27D,
                collateralLocked: 34000000000000000000,
                usdcLent: 70016404,
                usdcBorrowed: 70026271
            })
        );

        records.push(
            Record({
                user: 0xA811c306557370B90Cf92F207d94ab43D0FaF013,
                collateralLocked: 10000000000000000000,
                usdcLent: 20596858,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xc73622FFf7A789B014926926533Fb93278816b49,
                collateralLocked: 0,
                usdcLent: 41714332,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x1c95Ab93F8971CC774B27c39ee3561FA335bDdEe,
                collateralLocked: 0,
                usdcLent: 400038614,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x562aDCDCf5fEfA4ABaBA8d634125B20Ef643beC1,
                collateralLocked: 500000000000000,
                usdcLent: 6511589044,
                usdcBorrowed: 353
            })
        );

        records.push(
            Record({
                user: 0xF86D1595E7B66FfeE70dDBb3DDeE16430D989f3E,
                collateralLocked: 0,
                usdcLent: 200243703,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x9D8Db12174db797EF9ff38437596110f54Dc560c,
                collateralLocked: 0,
                usdcLent: 200078224,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x5c8fde92804F77A94E1797Cf5f095e4f82897cd1,
                collateralLocked: 0,
                usdcLent: 3331550277,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x291ba4427273077E9ce1Ff9117e39489A161C0D1,
                collateralLocked: 0,
                usdcLent: 129583881,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x8E72bCAAafba328b17d3167b32E9049C3c946fCc,
                collateralLocked: 20408200000000000000,
                usdcLent: 55120415,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xd99Fb6981dE228f7BcF794f8c4D064c41caf4D76,
                collateralLocked: 100000000000000000,
                usdcLent: 1841,
                usdcBorrowed: 3374
            })
        );

        records.push(
            Record({
                user: 0xe0bDda85ca88dECa04254cE6203A1495A1d2730F,
                collateralLocked: 0,
                usdcLent: 74000585,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x00fc76b7Ab78BE850fA8112c792502C0601C6096,
                collateralLocked: 500000000000000,
                usdcLent: 1615,
                usdcBorrowed: 18
            })
        );

        records.push(
            Record({
                user: 0x437493d7Cb4B6cD20fe502399B9ad7bCbb9a83FE,
                collateralLocked: 139374200000000000000,
                usdcLent: 319662636,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x6132947a740b485899642e6e04aF62eC4a22DA1F,
                collateralLocked: 0,
                usdcLent: 5632,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xd00f0EcFeF48418e726991f7aB5073c0E08aEF9A,
                collateralLocked: 0,
                usdcLent: 400519485,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x1834A16Ceb4C5c3B963F4659A50064F8a97DDE55,
                collateralLocked: 0,
                usdcLent: 510,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({user: 0xAdE62B3B77fBC8f25c6a95C1999220455C2C742e, collateralLocked: 0, usdcLent: 5, usdcBorrowed: 0})
        );

        records.push(
            Record({
                user: 0xaf79A0E5F35F2A6D86e9EbfDb3738D06B32Ea9a6,
                collateralLocked: 0,
                usdcLent: 205352383,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xc8419D7f4D579548179F5C8Ba4B5e8FCadCF3AF0,
                collateralLocked: 0,
                usdcLent: 122159114,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x5b7D41e6bbba99ABC14172dD51F7De94c5c2a961,
                collateralLocked: 0,
                usdcLent: 10107049850,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x910a020813dfb2FFE7F54fF801E532d38edD3144,
                collateralLocked: 0,
                usdcLent: 823,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x43cebE05a4c748a99Dc47DFf33EF53E5EB75CAEc,
                collateralLocked: 152119200000000000000,
                usdcLent: 0,
                usdcBorrowed: 100775049
            })
        );

        records.push(
            Record({
                user: 0x1ad327e031D1Ec46476A6211Cb5e0c072AE51a6D,
                collateralLocked: 4400000000000000,
                usdcLent: 18206,
                usdcBorrowed: 4910
            })
        );

        records.push(
            Record({
                user: 0x419e98cAe40DB7504A9366753a6e25a5046470a1,
                collateralLocked: 0,
                usdcLent: 115148637,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x33b1Cfaba02Eb4B01810774443A9C2F47A28c5eE,
                collateralLocked: 0,
                usdcLent: 2187,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x3fC5eec5E38130B2F80fAc354e0B67D083b43335,
                collateralLocked: 0,
                usdcLent: 27475744,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xa6cfF5f3690066cC3838f6fad458E97F41eEB2b2,
                collateralLocked: 1000000000000000,
                usdcLent: 178242377,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xc8477Ae5eDD9DC7De588A46F47EE0c391e59B600,
                collateralLocked: 0,
                usdcLent: 2945,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x6AAAFb4d548338a9D4795921F557329Be3395a67,
                collateralLocked: 0,
                usdcLent: 9848,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xCd176d0e48e000B4e9CA475f277584FaA2DE5195,
                collateralLocked: 0,
                usdcLent: 1828317279,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xF95A86005BC440Ea63e1C57E5428A30bF2C67FB6,
                collateralLocked: 10000000000000000,
                usdcLent: 78953,
                usdcBorrowed: 4737
            })
        );

        records.push(
            Record({
                user: 0x869e0185D71cC1BA6e7eA7277d6c4AA75933b665,
                collateralLocked: 0,
                usdcLent: 7494,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x0D8C40Ab2F2a67DF76892Ec15A368dE297f5A6d7,
                collateralLocked: 955600000000000000,
                usdcLent: 96035,
                usdcBorrowed: 6259
            })
        );

        records.push(
            Record({
                user: 0x09eD2dd6eF3542958fFbCE35a0C7B7c4A575471a,
                collateralLocked: 50000000000000000000,
                usdcLent: 100130028,
                usdcBorrowed: 80129184
            })
        );

        records.push(
            Record({
                user: 0x63FA661C8B1F85DD7B9F66fbdAd4c4fA7FE97e00,
                collateralLocked: 0,
                usdcLent: 70014841150,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xCF730EAe39b1c81Cf2C9Ece2aC4DdCDE8028e2D5,
                collateralLocked: 500000000000000,
                usdcLent: 300380957,
                usdcBorrowed: 14
            })
        );

        records.push(
            Record({
                user: 0x985ca6F476E868a7EE656F3fbc83DD25D68D4307,
                collateralLocked: 0,
                usdcLent: 12337789730,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xF7E383DbC19a765ed57340d28B018549ebFFb52d,
                collateralLocked: 0,
                usdcLent: 380601053,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x9Ac01740796907c7183299B91e3E14839d34A91B,
                collateralLocked: 0,
                usdcLent: 728588,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x0c35707e42b9716C1B12D30F4D5AED0040a6A667,
                collateralLocked: 29649100000000000000,
                usdcLent: 50017619,
                usdcBorrowed: 50026222
            })
        );

        records.push(
            Record({
                user: 0x2271723756a61799119cc66DD53fd8894896e9E8,
                collateralLocked: 10000000000000000000,
                usdcLent: 21518027,
                usdcBorrowed: 7649161
            })
        );

        records.push(
            Record({
                user: 0xbB6bd3d5bb121853Ffc3a3Aa24Ca59ABad6402be,
                collateralLocked: 106672000000000000000,
                usdcLent: 3188,
                usdcBorrowed: 168580251
            })
        );

        records.push(
            Record({
                user: 0xE1C05C1AD7094Bd712989C5C8A0B271Efd4A8BCA,
                collateralLocked: 0,
                usdcLent: 38560252,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xc8F59918bf67d2B18BBFC3BB3C1F2183AB1840cc,
                collateralLocked: 39830000000000000000,
                usdcLent: 0,
                usdcBorrowed: 65731563
            })
        );

        records.push(
            Record({
                user: 0x43eC24769444D9cea756D52543B5F0c72a330172,
                collateralLocked: 86740000000000000000,
                usdcLent: 108542488,
                usdcBorrowed: 100016204
            })
        );

        records.push(
            Record({
                user: 0x4CB6bdD49372E998b1DbFaB47ad78Bfa9d15CaD1,
                collateralLocked: 150000000000000000000,
                usdcLent: 300293425,
                usdcBorrowed: 300362179
            })
        );

        records.push(
            Record({
                user: 0x4675Fd692288a3e88e302b828d94BC07c90449dc,
                collateralLocked: 0,
                usdcLent: 336,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x4AAA2c30f8094e534280778735E2CD17E3C3D031,
                collateralLocked: 0,
                usdcLent: 49236,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xBD4f9f03E927E012Bac212E6AC1755D1F1846257,
                collateralLocked: 0,
                usdcLent: 608,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x524b17C6ECbCD0230583407980fcd2eD6e3748De,
                collateralLocked: 0,
                usdcLent: 504146424700,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x6275C445FeA7B734D37eef3E6476aC7E299B182f,
                collateralLocked: 0,
                usdcLent: 798,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xc81Ecf6DA310927b9e2018e0C697d9d1FC003eC8,
                collateralLocked: 700000000000000,
                usdcLent: 75022843,
                usdcBorrowed: 1361
            })
        );

        records.push(
            Record({
                user: 0x38FE78B464761B99402D29Bb9c86568E9e6DF7E5,
                collateralLocked: 234677002500000,
                usdcLent: 5705,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x249f5c7E9D0C6721cE48A65b5F56C5067b96D29A,
                collateralLocked: 200000000000000,
                usdcLent: 2183998967,
                usdcBorrowed: 3
            })
        );

        records.push(
            Record({
                user: 0x044935732148a3b12A5d0eA2f50F991d77243f92,
                collateralLocked: 625000000000000000000,
                usdcLent: 3326455795,
                usdcBorrowed: 746638375
            })
        );

        records.push(
            Record({
                user: 0x666120151A45797f01e932538e3F8D00C660631b,
                collateralLocked: 0,
                usdcLent: 125113150,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xBE21Bb383F7FFF1bcE643AC9293f34e2E81EAf85,
                collateralLocked: 0,
                usdcLent: 180235012,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xA5A73B1B3113e31F704633674BCfE091565e8B13,
                collateralLocked: 0,
                usdcLent: 1345232185,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x42d49141dD31E56cF9619dB6FEDE21229cf4d873,
                collateralLocked: 300000000000000,
                usdcLent: 0,
                usdcBorrowed: 82
            })
        );

        records.push(
            Record({
                user: 0xA688937299999548fa8F032141AD70BC988CE336,
                collateralLocked: 0,
                usdcLent: 1105339179,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x2A40785d2Da725599FF66477438af62dFcc0f44B,
                collateralLocked: 0,
                usdcLent: 79300613,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x041331231C6727403ADA5AeE33b8988D5063fC76,
                collateralLocked: 500000000000000,
                usdcLent: 200534374,
                usdcBorrowed: 8
            })
        );

        records.push(
            Record({
                user: 0xDeb70C7346aa8f288fe48e31E7ED39e4E2754212,
                collateralLocked: 0,
                usdcLent: 331848493,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xB609316dec60d2bB1B8f50DDc54a7D169F442158,
                collateralLocked: 64000000000000000,
                usdcLent: 3,
                usdcBorrowed: 1471
            })
        );

        records.push(
            Record({
                user: 0x525a2594688F0D7a011078738E0b4B62D2fe3Def,
                collateralLocked: 0,
                usdcLent: 297714109,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x5457C2dbB3EbE468481193be1786FA8190e66D21,
                collateralLocked: 300000000000000,
                usdcLent: 2804,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x04321E7E28769e77B46dDAF97713A364a1893584,
                collateralLocked: 0,
                usdcLent: 333766326,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x76885d8271A0ce5Bf771dcf9e305Cb73a6e0B1a2,
                collateralLocked: 0,
                usdcLent: 87632339,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xBbdAdB8D3903C3Cc8876Bbbe401Eaf9f12B78F06,
                collateralLocked: 0,
                usdcLent: 73693139,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x79c9Af53C329889fb6560244caB73212984461d1,
                collateralLocked: 1073383000000000000,
                usdcLent: 78,
                usdcBorrowed: 352837
            })
        );

        records.push(
            Record({
                user: 0x132462224f7E0da01781D8343c4B95300CDBe84E,
                collateralLocked: 0,
                usdcLent: 69087802,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xF82F93fdDc53726d49C0Ef793229d747F3323A81,
                collateralLocked: 0,
                usdcLent: 45317323,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x69574f6C1e7527E46e02481fFa9F396a020102E6,
                collateralLocked: 0,
                usdcLent: 1001305597,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x364482A404171B8135DF6E3FA6AfDcAd973E9661,
                collateralLocked: 0,
                usdcLent: 2780166774,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xed4f249EbD8bBF4fb18ddbEd97808066a13E5CBe,
                collateralLocked: 0,
                usdcLent: 108584,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x934cC16F2c7dfc0816e087d1C1A0647C9AB0694c,
                collateralLocked: 0,
                usdcLent: 392295347500,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xa5c646a304C88051Ca8521D8170520E807A88260,
                collateralLocked: 149749699999999983616,
                usdcLent: 11127714740,
                usdcBorrowed: 287374703
            })
        );

        records.push(
            Record({
                user: 0x7bFF2C940C333564E7199F0c80bcbA9E84ECf234,
                collateralLocked: 0,
                usdcLent: 86451794,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xCC434AdEebC5374ad4712DC252395a30aAD1681B,
                collateralLocked: 2227266379999999950848,
                usdcLent: 17006421150,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xAC1280955993d80961b169bf97874Ec781b047D3,
                collateralLocked: 0,
                usdcLent: 180838372,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xf60222db3f9930093bDf574B23d0Dd59fF3E6997,
                collateralLocked: 3000000000000000,
                usdcLent: 100023980,
                usdcBorrowed: 3910
            })
        );

        records.push(
            Record({
                user: 0x0d12DD469d710A910D053fe6B04cd37875bAa335,
                collateralLocked: 0,
                usdcLent: 77367,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xBabbAb46D33d4C24474B83c484228D3b618b30F0,
                collateralLocked: 10000000000000000,
                usdcLent: 21908857,
                usdcBorrowed: 300
            })
        );

        records.push(
            Record({
                user: 0x66007079aCbebB3Fb5261B4ED0818f4c0542Aa5A,
                collateralLocked: 90210700000000000000,
                usdcLent: 1686115605,
                usdcBorrowed: 125942988
            })
        );

        records.push(
            Record({
                user: 0x6b46C82023ED3d23B89A14D932533E315BEfCCbb,
                collateralLocked: 0,
                usdcLent: 24288503,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xBF993C2b812Ef91DF6b41ad601Bc1F6Ad1CdE590,
                collateralLocked: 0,
                usdcLent: 25913522,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xAcb22b1842adC500E741298d3F62e294760cd09E,
                collateralLocked: 0,
                usdcLent: 1578,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xa69e608fc12a97721ABd71f6a78BDd62D72eEbEA,
                collateralLocked: 0,
                usdcLent: 7123,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x5D02Be5857E4298EaD53D32D06bd820A447D0151,
                collateralLocked: 0,
                usdcLent: 2435669195,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x3779679695bF963A24F10D5B17B34D5E8cCFf9C6,
                collateralLocked: 600000000000000,
                usdcLent: 12292335350,
                usdcBorrowed: 236
            })
        );

        records.push(
            Record({
                user: 0x89C4984c0A332964e5aCc0a3fa875db56FcA91B7,
                collateralLocked: 30113000000000000000,
                usdcLent: 50065384,
                usdcBorrowed: 50082604
            })
        );

        records.push(
            Record({
                user: 0xC3ffD33d56FdB24C8E1e9f6B27220Ef906c851e9,
                collateralLocked: 300000000000000,
                usdcLent: 111600770,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x9D043B4216aa04C9Dbf2692AeD7E90f6aB9CFb47,
                collateralLocked: 2500000000000000,
                usdcLent: 29039,
                usdcBorrowed: 2747
            })
        );

        records.push(
            Record({
                user: 0x22c79704f468168b52ff3D6BACf4D0052CFC2526,
                collateralLocked: 500000000000000,
                usdcLent: 5446,
                usdcBorrowed: 1
            })
        );

        records.push(
            Record({
                user: 0x805D79C9432e85B6B27a52dF429e47a82F43864A,
                collateralLocked: 74743000000000000000,
                usdcLent: 0,
                usdcBorrowed: 90936063
            })
        );

        records.push(
            Record({
                user: 0x6ea38aD5C1954ffC8dBb41662E4866D41c9f47f2,
                collateralLocked: 22500000000000000000,
                usdcLent: 120029434,
                usdcBorrowed: 30003807
            })
        );

        records.push(
            Record({
                user: 0x17Ba700D996ff804228099ca9eFf3C6601DEFFc9,
                collateralLocked: 0,
                usdcLent: 3239,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x6cf49DCA9fA4711d6c2571F42ecdabC14392f94b,
                collateralLocked: 20011000000000000000,
                usdcLent: 35045647,
                usdcBorrowed: 35057520
            })
        );

        records.push(
            Record({
                user: 0x5b48Dc32eEbeaA9Df9D83585F214172B7f57Fe82,
                collateralLocked: 0,
                usdcLent: 5874,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x7522344f52d503fD1B214B5D3d3497133E8CB789,
                collateralLocked: 0,
                usdcLent: 47650049,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x4AF56fD53ECdE6D1B7E6E171213a06E2969aFEb2,
                collateralLocked: 161000456999999995904,
                usdcLent: 650024696,
                usdcBorrowed: 500017416
            })
        );

        records.push(
            Record({user: 0xA1a6590e6e8c08697232B0f4910E020fb2D0344A, collateralLocked: 0, usdcLent: 5, usdcBorrowed: 0})
        );

        records.push(
            Record({
                user: 0x5Bc0288b62359D7852aE6BA340499A1fCa46cF91,
                collateralLocked: 0,
                usdcLent: 38760345,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x359c045137b002fe6DA7944cAB1eDD1c5D62f29b,
                collateralLocked: 0,
                usdcLent: 55645776,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x0892f198e82af563C13D8234D329dE30D8870cf8,
                collateralLocked: 0,
                usdcLent: 1001160203,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({user: 0xFb78B91B9a95087CBc0538c35ac6763900cAdc0F, collateralLocked: 0, usdcLent: 8, usdcBorrowed: 0})
        );

        records.push(
            Record({
                user: 0x7971359188c2389B08947d0C0B5E66eFca64d6FC,
                collateralLocked: 35486199999999995904,
                usdcLent: 20573065,
                usdcBorrowed: 14003141
            })
        );

        records.push(
            Record({
                user: 0x0e183a2CD246eFb5649008954017e732F6895b33,
                collateralLocked: 0,
                usdcLent: 500652863,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xBb1fBEB2b23374a77383c762Ff9e1bA1f4cc6Ddd,
                collateralLocked: 0,
                usdcLent: 69955464,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xe61D3009A18918CfEDD9EC51b48e0468a12003d5,
                collateralLocked: 400000000000000,
                usdcLent: 4166,
                usdcBorrowed: 19
            })
        );

        records.push(
            Record({
                user: 0xF69b4D29000Fa63849B76f93f826400AaB06145C,
                collateralLocked: 0,
                usdcLent: 254331369,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xD939c6f7B8F2e830111Aa61a591EE94A0FB7f1c6,
                collateralLocked: 2000000000000000,
                usdcLent: 1541,
                usdcBorrowed: 3127
            })
        );

        records.push(
            Record({
                user: 0x1f9E6ceA3F3300E882E89e03F8d2598c0a04B88A,
                collateralLocked: 406000000000000000000,
                usdcLent: 2090,
                usdcBorrowed: 542348109
            })
        );

        records.push(
            Record({
                user: 0xaef893d47A071dc7013984143ffa4E5412422738,
                collateralLocked: 300000000000000,
                usdcLent: 8006,
                usdcBorrowed: 39
            })
        );

        records.push(
            Record({
                user: 0x46661F6c25724101e8e39Eec123ab501aFf460F8,
                collateralLocked: 0,
                usdcLent: 25032604,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x0Ed247C6d77B5474f99d8500804de8dFdDe87FBD,
                collateralLocked: 1081522899999999918080,
                usdcLent: 500622394,
                usdcBorrowed: 500750284
            })
        );

        records.push(
            Record({
                user: 0xF18a914C1Bb4D5Fbf1baee8d3909470b8AfAbAEf,
                collateralLocked: 0,
                usdcLent: 24031278,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xef215cD1Ec48aeA4Dad1F9f22EB3c8D85Fc0176C,
                collateralLocked: 0,
                usdcLent: 74762043,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xD90FCBdcAc3D957Ab0D04211A80Ce270f8FbC9b0,
                collateralLocked: 0,
                usdcLent: 353,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x4622370c3dbCf7B34fe25d52958c564A7DEA5F8a,
                collateralLocked: 0,
                usdcLent: 227,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x69241986E22eA201970Ce455f2C903662b3D503A,
                collateralLocked: 0,
                usdcLent: 31116763,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x3e1Ab3bDf5e8Df3Dd3f8f7DB87A8dF5D5ee41f65,
                collateralLocked: 0,
                usdcLent: 27567713,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xC317A1a5BeCa9B38d68d69a71a7Eb2b4e2803d24,
                collateralLocked: 0,
                usdcLent: 24031263,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x633921f5FC7616945FBdd1c0B87d9196c859edd1,
                collateralLocked: 0,
                usdcLent: 3700197019,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x9EeA9C32196F4A03a03B173803a72f43b3Fe31E0,
                collateralLocked: 0,
                usdcLent: 4035971465,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({user: 0x6eD262743175AF025AB026173Eccb4ac40Ce5132, collateralLocked: 0, usdcLent: 2, usdcBorrowed: 0})
        );

        records.push(
            Record({
                user: 0xB604229540Ae0A8286c014AF2E1366cC8f17BCc6,
                collateralLocked: 0,
                usdcLent: 78701687,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xa87b8A373372Efb59891BC169942e036F8a2b12b,
                collateralLocked: 0,
                usdcLent: 6745,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xc199D6Dc0691B3fA0Ef23b8F1Cdc1bABF30C86F9,
                collateralLocked: 1554140442000000000,
                usdcLent: 2565,
                usdcBorrowed: 114726
            })
        );

        records.push(
            Record({user: 0x6703E30Dd62cEd082B8c817909ffb23fF1565423, collateralLocked: 0, usdcLent: 2, usdcBorrowed: 0})
        );

        records.push(
            Record({
                user: 0x18E3Dc16c699468558835D52069b64595ADAc375,
                collateralLocked: 0,
                usdcLent: 196658679,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({user: 0xB51081e0Ec832B055188d16bAfe03734408bBd61, collateralLocked: 0, usdcLent: 0, usdcBorrowed: 0})
        );

        records.push(
            Record({
                user: 0xf9e2E3F36C45F31ef4579c481C040772f086577b,
                collateralLocked: 1330877629999999776456704,
                usdcLent: 3874,
                usdcBorrowed: 2627779980000
            })
        );

        records.push(
            Record({
                user: 0xC841C7b66bC6300449C5a9eCbE85Fc910bb82892,
                collateralLocked: 523404688699999977472,
                usdcLent: 0,
                usdcBorrowed: 660848916
            })
        );

        records.push(
            Record({
                user: 0x5A7150F73b2203dd01cDeA5DC5B20E99DbE3639B,
                collateralLocked: 0,
                usdcLent: 1001304233000,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x0a09013E8E4a6431C7496110EfdcBD8a60D2dbDA,
                collateralLocked: 1000000000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x669a81862A77fB70E0818f84eA69b0F3C73C7836,
                collateralLocked: 100,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({user: 0x69B624370c13C275747f829284EA2e3c13930b90, collateralLocked: 0, usdcLent: 0, usdcBorrowed: 0})
        );

        records.push(
            Record({
                user: 0xE73965EAbE1193b360E7Aa8c2d042988D17BD93c,
                collateralLocked: 1000000000000000000,
                usdcLent: 0,
                usdcBorrowed: 1001619
            })
        );

        records.push(
            Record({
                user: 0x930ab1c857585467E9b3Ed76fa5cCF9498283546,
                collateralLocked: 1000000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xa5a600b404729cC8E7efC3978754a0F9AD19b3a7,
                collateralLocked: 2344800000000000000,
                usdcLent: 0,
                usdcBorrowed: 4744905
            })
        );

        records.push(
            Record({
                user: 0xe56bbB2D1A3C77dBfEca02361e154F5a6df4D874,
                collateralLocked: 100000000000000000,
                usdcLent: 0,
                usdcBorrowed: 14441
            })
        );

        records.push(
            Record({
                user: 0xC4E54394735abB581c85ecbD7bdF395a6a0093E4,
                collateralLocked: 30634900000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xBE18bEfe347cC0390aBc2B25f60344A3d98A548B,
                collateralLocked: 1034400000000000000,
                usdcLent: 0,
                usdcBorrowed: 3170419
            })
        );

        records.push(
            Record({
                user: 0x1774f58C4f22368A0154Ac00f39e7cc70b4DA3E2,
                collateralLocked: 300000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x8516cFEbDe7545ff5F7d0001b71Df9fB68e3130E,
                collateralLocked: 55740000000000000000,
                usdcLent: 0,
                usdcBorrowed: 24
            })
        );

        records.push(
            Record({
                user: 0x259cD8a85c5ECaaaB55E1b961F09bd52CD744377,
                collateralLocked: 25000000000000000000,
                usdcLent: 0,
                usdcBorrowed: 40020178
            })
        );

        records.push(
            Record({
                user: 0xBCF62D3771799EFe8Db0804477B74E6b02aa7ACd,
                collateralLocked: 1000000000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x97759FFc1A1efCe66CD33f827e236FB93cC79888,
                collateralLocked: 337856899999999983616,
                usdcLent: 0,
                usdcBorrowed: 621011428
            })
        );

        records.push(
            Record({
                user: 0x70ff345B598ddfa40711177182990be62BE12C0E,
                collateralLocked: 17416599999999997952,
                usdcLent: 0,
                usdcBorrowed: 20003336
            })
        );

        records.push(
            Record({
                user: 0x50F8d3bd8b3E02254BA2E092eb0d73f4ccaed4bD,
                collateralLocked: 1000000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x4F9F1c7b9fE78dD394e28CCEa16cb8D0465E61f1,
                collateralLocked: 102444100000000000000,
                usdcLent: 0,
                usdcBorrowed: 200288673
            })
        );

        records.push(
            Record({
                user: 0x337B9727E78C18b8D5111f787A9ae5Fdc7E54897,
                collateralLocked: 1000000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x8a87958ee9b6E354987C43629aF60F08Ece7ddC4,
                collateralLocked: 1000000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x08cDD3dF0922268B0B3576F0C8bE1a7a11Da8AeE,
                collateralLocked: 147598000000000000000,
                usdcLent: 0,
                usdcBorrowed: 310325668
            })
        );

        records.push(
            Record({
                user: 0x8f82365f4D754B877440EAa900E3B7cD9E218a32,
                collateralLocked: 4000000000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x8294665B327062f65ea6980DeB42F280f380da2e,
                collateralLocked: 1000000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x6fbEB648BbD08F59A225B034026F73Dff9DaD1C6,
                collateralLocked: 36490000000000000000,
                usdcLent: 0,
                usdcBorrowed: 20002670
            })
        );

        records.push(
            Record({
                user: 0x7A04605FC8ad994B21957DA7a8846F88cB18CaEd,
                collateralLocked: 883900200000000098304,
                usdcLent: 0,
                usdcBorrowed: 1463459006
            })
        );

        records.push(
            Record({
                user: 0x689E4f225c4Fb738d8148514F7cdDb0749767870,
                collateralLocked: 1922325199999999934464,
                usdcLent: 0,
                usdcBorrowed: 3355833580
            })
        );

        records.push(
            Record({
                user: 0xd1f3b946887dD5BE9cF532010256DBf218a18463,
                collateralLocked: 1000000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x8402c53069aB5dE02cf0747e5AbC99EedA734597,
                collateralLocked: 100000000000000000,
                usdcLent: 0,
                usdcBorrowed: 2823
            })
        );

        records.push(
            Record({user: 0x6C5FBd641c5D3DD0E2631c6EB5c0c91a0F7e60c1, collateralLocked: 0, usdcLent: 0, usdcBorrowed: 0})
        );

        records.push(
            Record({
                user: 0x37fc58fc96990f454781771fe6358CAd35bd3556,
                collateralLocked: 400000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xbb14fb6F2a2b8DB4AA924d561e4b7CBd7AB464fE,
                collateralLocked: 2100000000000000,
                usdcLent: 0,
                usdcBorrowed: 4090
            })
        );

        records.push(
            Record({
                user: 0x25fAa8a17F6B1ec8D85fE52d06CbD083c5D0FE84,
                collateralLocked: 28700000000000000,
                usdcLent: 0,
                usdcBorrowed: 55236
            })
        );

        records.push(
            Record({
                user: 0xA74d78caE00a164304F4729843266AD9279D2631,
                collateralLocked: 140167100000000000000,
                usdcLent: 0,
                usdcBorrowed: 121421434
            })
        );

        records.push(
            Record({
                user: 0x6853Ad3e1FaA6DBf027773596240d79cDD84e38F,
                collateralLocked: 33393300000000004096,
                usdcLent: 0,
                usdcBorrowed: 52768701
            })
        );

        records.push(
            Record({
                user: 0xab7bF3096E69FCbDcF6d524E95496448DebF7bA9,
                collateralLocked: 21666200000000000000,
                usdcLent: 0,
                usdcBorrowed: 30049523
            })
        );

        records.push(
            Record({
                user: 0xb231EB2A8029dbffBD2D91aE9d134768095a2D58,
                collateralLocked: 500000000000000,
                usdcLent: 0,
                usdcBorrowed: 681
            })
        );

        records.push(
            Record({
                user: 0xF95E2544ad4Fa8008E6b5a88ceDc4E14d6C60856,
                collateralLocked: 300000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xF693F37d31e5e57Bef9f7aEe01D5EEf3C2A843C1,
                collateralLocked: 300940284000000000,
                usdcLent: 0,
                usdcBorrowed: 22333
            })
        );

        records.push(
            Record({
                user: 0x56dF41615cF3A28B151Fd63268Cd772f5D636F64,
                collateralLocked: 1000000000000000000,
                usdcLent: 0,
                usdcBorrowed: 36410
            })
        );

        records.push(
            Record({
                user: 0xe70D804197627c7C6c495be5F0bC0fACfa98606E,
                collateralLocked: 671674899999999918080,
                usdcLent: 0,
                usdcBorrowed: 900131454
            })
        );

        records.push(
            Record({
                user: 0x8BE8FAc5Cf73354719301c25Fd41a9373fa8D9Ac,
                collateralLocked: 1000000000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x641643c8745E2f0cf96A83d599524712287F26C3,
                collateralLocked: 1000000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x63F99b6206568bCD7815667A75351D3aEDE9430c,
                collateralLocked: 816000000000000000,
                usdcLent: 0,
                usdcBorrowed: 1239034
            })
        );

        records.push(
            Record({
                user: 0x70187b7A5743aFC7b3D8690E00f3d26d42d90196,
                collateralLocked: 1000000000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x4F7079065c0496311a3eDb7f42C73dcF21Ef8D56,
                collateralLocked: 100000000000000000,
                usdcLent: 0,
                usdcBorrowed: 9646
            })
        );

        records.push(
            Record({
                user: 0x27F2eACc011ecA4165eb7d44815238A03DC768b5,
                collateralLocked: 400000000000000,
                usdcLent: 0,
                usdcBorrowed: 22
            })
        );

        records.push(
            Record({
                user: 0xa7ca3B622951cE2916E35694efD0d7b80275Fa6f,
                collateralLocked: 1000000000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({user: 0x28420Eb1FD1323f2985729C477316525d95C23d8, collateralLocked: 0, usdcLent: 0, usdcBorrowed: 0})
        );

        records.push(
            Record({
                user: 0x715c10A781C7C0c9B6bC46b482860aB450eb8F15,
                collateralLocked: 1000000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({user: 0xf7C260F74D60dbEC275BB5d8b5a3108aE9947058, collateralLocked: 0, usdcLent: 0, usdcBorrowed: 0})
        );

        records.push(
            Record({
                user: 0x940EB12Efdc3E636C90a10b6F2DBb9491eE48dE3,
                collateralLocked: 1282000000000000,
                usdcLent: 0,
                usdcBorrowed: 282
            })
        );

        records.push(
            Record({
                user: 0x73934056B63E74e24a5B9fd32389FF9dBD5dB327,
                collateralLocked: 1000000000000000000,
                usdcLent: 0,
                usdcBorrowed: 819240
            })
        );

        records.push(
            Record({
                user: 0x024a522daA4a1d46bA8395b5455C7d26F36c2981,
                collateralLocked: 1000000000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x78e29D0aA06F22fE5A3F6b71B90f7a37a63b7F9A,
                collateralLocked: 300000000000000,
                usdcLent: 0,
                usdcBorrowed: 68
            })
        );

        records.push(
            Record({
                user: 0xD5d7540cCef6c99BE67486AC2b8d317FfC6544EA,
                collateralLocked: 5646200000000000000,
                usdcLent: 0,
                usdcBorrowed: 1000184
            })
        );

        records.push(
            Record({
                user: 0xdd00344964E6ab036Ea5d1273486aeFBc6A41D3f,
                collateralLocked: 2000000000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xB332F121C13FE65B80B53453BD1c925a6677adde,
                collateralLocked: 20000000000000,
                usdcLent: 0,
                usdcBorrowed: 39
            })
        );

        records.push(
            Record({user: 0x3E904FC8d4838d223E37Bc0327613839A57ff9b0, collateralLocked: 0, usdcLent: 0, usdcBorrowed: 0})
        );

        records.push(
            Record({
                user: 0x0B475E5f6ef7B2f840fF43d8d564205A1e5eD84A,
                collateralLocked: 500000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xd4e73F42fa247D1682D6f31e6eB8c5e96dC8B0E4,
                collateralLocked: 300000000000000,
                usdcLent: 0,
                usdcBorrowed: 22
            })
        );

        records.push(
            Record({
                user: 0xFD25bBF856B8B290095cA4632bEc1fB26aa5D8BA,
                collateralLocked: 100,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xAf14Ee23DA58D4Be2b74f4811931E3bD2EEf109A,
                collateralLocked: 106572600000000000000,
                usdcLent: 0,
                usdcBorrowed: 200216345
            })
        );

        records.push(
            Record({
                user: 0x7Cb2c41aD96f12DaE5986006C274278122EabC7a,
                collateralLocked: 10000000000000000,
                usdcLent: 0,
                usdcBorrowed: 19
            })
        );

        records.push(
            Record({
                user: 0x410151832cEBc39a0438149597611B7B3505002F,
                collateralLocked: 1257000000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xd075eCAcC401B45d04D15a822e4942A7464129CA,
                collateralLocked: 9590600000000000000,
                usdcLent: 0,
                usdcBorrowed: 24891321
            })
        );

        records.push(
            Record({
                user: 0x2e5b575BB803324d616f761FEEA0C19C03B6F77d,
                collateralLocked: 1138818500000000114688,
                usdcLent: 0,
                usdcBorrowed: 1502462571
            })
        );

        records.push(
            Record({
                user: 0x23335C18DdA0078abbb21B2571daf7334aeb6674,
                collateralLocked: 300000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x2464225C5Cc10D1f017EB0c40DCcB0E692B5b575,
                collateralLocked: 325836899999999983616,
                usdcLent: 0,
                usdcBorrowed: 375388589
            })
        );

        records.push(
            Record({
                user: 0xbB772295D4E8a8266e5c11248A691EDA991d96E5,
                collateralLocked: 33000000000000000000,
                usdcLent: 0,
                usdcBorrowed: 50003930
            })
        );

        records.push(
            Record({
                user: 0xdAa4dABEC8626C537F59a6073bD35FB0A1290350,
                collateralLocked: 8100000000000000,
                usdcLent: 0,
                usdcBorrowed: 10564
            })
        );

        records.push(
            Record({
                user: 0x33C33ee73ee6CdBE244D01B5620c147506F39C66,
                collateralLocked: 400000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x7BB3b22c50e31F5bF39c851C0072A3394D767608,
                collateralLocked: 144477592900000000,
                usdcLent: 0,
                usdcBorrowed: 10809
            })
        );

        records.push(
            Record({
                user: 0xfC9da8dFdd89383Ad0d6a5887138FE630f201c61,
                collateralLocked: 400000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xFD3532740123B7638e26F349c1C81Bb683577089,
                collateralLocked: 1000000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x7D634Ed6edD45273A69FEc8eCEcE39B866FFaacD,
                collateralLocked: 10730000000000000000,
                usdcLent: 0,
                usdcBorrowed: 5001087
            })
        );

        records.push(
            Record({user: 0xb8A78491DE9aD82C0f9ec6b3FFe45414Acb1667f, collateralLocked: 0, usdcLent: 0, usdcBorrowed: 0})
        );

        records.push(
            Record({
                user: 0xb4d907E9039adEd6247a622Efb58378bd4eab307,
                collateralLocked: 10000000000000000000,
                usdcLent: 0,
                usdcBorrowed: 3664
            })
        );

        records.push(
            Record({
                user: 0x703B4dfDd7A7D1a38CAc7f532579770118147C23,
                collateralLocked: 400000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0x5e9A8ffD0F55b8d195e7E653AABEF258B95dF253,
                collateralLocked: 1000000000000000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        records.push(
            Record({
                user: 0xc3e46D85b51Fc24C195756e07987B959d74CA1f3,
                collateralLocked: 40000000000000000,
                usdcLent: 0,
                usdcBorrowed: 4897
            })
        );

        records.push(
            Record({
                user: 0xB56ba08e1d21A6424787dA793126CD3A9272A34E,
                collateralLocked: 91984440770000000,
                usdcLent: 0,
                usdcBorrowed: 19887
            })
        );

        records.push(
            Record({
                user: 0xC42f37a8b36f6C4AE7f214989357A4fEcEb55Ea9,
                collateralLocked: 261185918100000,
                usdcLent: 0,
                usdcBorrowed: 0
            })
        );

        // Set User Info
        uint256 totalMintRecords = records.length;
        address[] memory users1 = new address[](totalMintRecords);
        uint256 totalCollateralLocked = 0;
        uint256 totalUsdcLent = 0;
        uint256 totalUsdcBorrowed = 0;
        for (uint256 i = 0; i < records.length; i++) {
            users1[i] = records[i].user;
            totalCollateralLocked += records[i].collateralLocked;
            totalUsdcLent += records[i].usdcLent;
            totalUsdcBorrowed += records[i].usdcBorrowed;
            infos.push(
                MorphoRepayment.UserInfo({
                    collateralLocked: records[i].collateralLocked,
                    usdcLent: records[i].usdcLent,
                    usdcBorrowed: records[i].usdcBorrowed,
                    usdcRepaid: 0,
                    isRepaid: false
                })
            );
        }

        _handleOps(
            abi.encodeWithSelector(MorphoRepayment.setUserInfo.selector, users1, infos), address(morphoRepayment)
        );

        assertEq(morphoRepayment.TOTAL_COLLATERAL(), totalCollateralLocked);
        assertEq(morphoRepayment.TOTAL_DEBT(), totalUsdcBorrowed);
        assertEq(morphoRepayment.TOTAL_USDC_LENT(), totalUsdcLent);

        assertEq(address(morphoRepayment), address(expectedAddress));
        assertEq(address(morphoRepayment.collateralToken()), address(K));
        assertEq(address(morphoRepayment.debtToken()), address(USDC));
        assertEq(morphoRepayment.totalCollateralUnlocked(), 0);
        assertEq(morphoRepayment.totalDebtRepaid(), 0);
        saveContractAddress("MorphoRepayment", address(morphoRepayment));
        saveContractAddress("MorphoRepayment-impl", address(impl));
    }
}
