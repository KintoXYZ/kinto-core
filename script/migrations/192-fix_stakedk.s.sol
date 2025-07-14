// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {StakedKinto} from "@kinto-core/vaults/StakedKinto.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FixStakedKinto is MigrationHelper {
    struct Record {
        address user;
        uint256 shares;
        bool mint;
    }

    Record[] public records;

    function run() public override {
        super.run();

        // vm.broadcast(deployerPrivateKey);

        StakedKinto stakedKinto = StakedKinto(payable(_getChainDeployment("StakedKinto")));
        if (address(stakedKinto) == address(0)) {
            console2.log("StakedKinto has to be deployed");
            return;
        }

        bytes memory bytecode = abi.encodePacked(type(StakedKinto).creationCode);

        _deployImplementationAndUpgrade("StakedKinto", "V12", bytecode);

        // ────────────────────── hack-cleanup records ──────────────────────

        // records.push(
        //     Record({user: 0xbd08200C3BD228118a9dBC7301Db93f71fCb96E5, shares: 61455800000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0xa8a0cb4E2DBbeC8057e69B1d4D69E5cF74EAc819, shares: 21666666649999900000, mint: true})
        // );
        // records.push(
        //     Record({user: 0xCAc1c83543d583A195ba976e5227C39C0719069e, shares: 16666666649999900000, mint: true})
        // );
        // records.push(
        //     Record({user: 0x850eD89D921fd18A4870bbE5ae889932e6c8fFaf, shares: 50013333333333200000, mint: true})
        // );
        // records.push(
        //     Record({user: 0xd17f5723742E43222b3A26d1ad2536a1AE0108fC, shares: 8364999999999900000, mint: true})
        // );
        // records.push(
        //     Record({user: 0x9F86444Cf2964403A3fA616385917a420FD4726C, shares: 8333333333333230000, mint: true})
        // );
        // records.push(
        //     Record({user: 0xA830D59962aebdF551A12ce2f53CeE2f6E731c86, shares: 944639600000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0x6bb4c01cc2430875751A5ddE0A466D987c0F1365, shares: 26048900000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0xd41feF730f89ae5D4A7bcB3AF0A92B2adB7FD058, shares: 34333300000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0x7534657ADac296FCfBE16BD08AF258E33BEe017A, shares: 18377800000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0x0A6d6a9f95E68f0aB78eB081b5b21760CCC67356, shares: 504419200000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0xb8310d4fa4460ec008FfFbe459451B848174e9F5, shares: 83616666666666500000, mint: true})
        // );
        // records.push(
        //     Record({user: 0x197Dc1B6723df7AeDeF7bB8198398D652CA322f0, shares: 8333333333333230000, mint: true})
        // );
        // records.push(
        //     Record({user: 0x974E38164B58f344098E865E981d8a33697FFB32, shares: 4166666666666560000, mint: true})
        // );
        // records.push(
        //     Record({user: 0x250D3D4Dd20B1817e52841B46cD4D48f6B4bCEea, shares: 219000000000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0xeead23E83AC9139ec420b1083467fa05EDE5616E, shares: 81151700000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0x6A5E1c3CCd58D0a6064C9229DaD012553d5BAe2C, shares: 42634600000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0xC2f77a505545798ED01c9304fa5A0abD4799F24A, shares: 49983333333333200000, mint: true})
        // );
        // records.push(
        //     Record({user: 0x31B2Dda4b9B16D092aF34b684d6b0cb2eb5f3BB5, shares: 49221000000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0xF3D78a8A457622F5016AC74EB1F37f3DA09e86Ad, shares: 8483333333333230000, mint: true})
        // );
        // records.push(
        //     Record({user: 0x7798Bae44Ccd533995EE6E67c40B1782a669E1d4, shares: 500000000000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0x69093227605061D43e44dC3852153DE1383aB2A9, shares: 11699999999999900000, mint: true})
        // );
        // records.push(
        //     Record({user: 0x24eC8285Ed0B8373B2eC753CbB668bCbB773d8Ab, shares: 506640500000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0x9ba6A569eB6c92Dfe30f90c0FF8EbD13FF316848, shares: 364000000000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0xda6f319fDaC0b5cddB33F65d41767B200Cb1702e, shares: 30013333333333200000, mint: true})
        // );
        // records.push(
        //     Record({user: 0xaF7E6463a5317ACC76De24cDC32DD1896825e768, shares: 101021800000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0x548719fBA49B4aF6ea1FB5AB7e806A934E408f5E, shares: 43543800000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0x9EeA9C32196F4A03a03B173803a72f43b3Fe31E0, shares: 1400408200000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0xe61D3009A18918CfEDD9EC51b48e0468a12003d5, shares: 354391100000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0x96A4fE77Db189b0F5Bd38bb0797e87eDF5081d8e, shares: 10039999983333200000, mint: true})
        // );
        // records.push(
        //     Record({user: 0xf59E927E4cF3d84acb808b3B8de6be7F2c67f215, shares: 157689700000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0xF3c1883d48a6Dfe248B2680C923552002dB34B16, shares: 712336400000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0xf80B444FeC79cC4f8F6f7D03505355f252dD1865, shares: 2127100000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0xc8477Ae5eDD9DC7De588A46F47EE0c391e59B600, shares: 71785600000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0x2B5650e8BD12F1df5ac15c3613949dC4Df6E8735, shares: 938024300000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0x6D987766D1c268694c88D243D0B7a34107A28577, shares: 1270283200000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0x03d35C5Ed389a3feA9Af8921C1B514c60B44e2c2, shares: 34733300000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0x1dB3C1376f99FDcC5B4c830776a2A56427599B71, shares: 117231300000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0x25499ce734F62cf5Fc8301999185d4A943297B6D, shares: 38179999999999900000, mint: true})
        // );
        // records.push(
        //     Record({user: 0x6b7d8C7682cc336DfE26CC3e5042459193808bec, shares: 12358600000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0xB41F2e4e157bd0279545121944b4fd4E059afe1a, shares: 9240000000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0xe53f1411665efBfbF7397eE6eE16A8A1dc08229C, shares: 1000000000000000000, mint: false})
        // );
        // records.push(
        //     Record({user: 0x22b72ea718C11e780aD293113A9C921BBcb3e4E1, shares: 4176166666666560000, mint: true})
        // );
        // records.push(
        //     Record({user: 0xb0a2B3e4469277bAC8E773Be4CDAE009848fba42, shares: 25333333333333200000, mint: true})
        // );
        // records.push(
        //     Record({user: 0x342cB256218EFf45705F023352b433659c566185, shares: 16666666666666500000, mint: true})
        // );
        // records.push(
        //     Record({user: 0xe403173f8DcBA7339b56d940DCD73C5CB29B1526, shares: 10416666666666500000, mint: true})
        // );
        // records.push(
        //     Record({user: 0xe847c816b99eB3f7f380B1B377c4c446743666d5, shares: 21194499999999900000, mint: true})
        // );
        // records.push(
        //     Record({user: 0xf26fe167A0f1ccd17f493fbD54bB840EDc1d889d, shares: 3036400000000000000, mint: false})
        // );

        // uint256 totalMintRecords = 19;
        // uint256 totalBurnRecords = records.length - totalMintRecords;
        // address[] memory users1 = new address[](totalMintRecords);
        // uint256[] memory shares1 = new uint256[](totalMintRecords);
        // uint256[] memory balances = new uint256[](records.length);
        // uint j = 0;
        // for (uint256 i = 0; i < records.length; i++) {
        //     if (records[i].mint) {
        //         users1[j] = records[i].user;
        //         shares1[j] = records[i].shares;
        //         j++;
        //     }
        //     balances[i] = stakedKinto.balanceOf(records[i].user);
        // }
        // _handleOps(
        //     abi.encodeWithSelector(StakedKinto.batchMintCurrentPeriodStake.selector, users1, shares1),
        //     payable(_getChainDeployment("StakedKinto"))
        // );

        // j = 0;
        // address[] memory users2 = new address[](totalBurnRecords);
        // uint256[] memory shares2 = new uint256[](totalBurnRecords);
        // for (uint256 i = 0; i < records.length; i++) {
        //     if (!records[i].mint) {
        //         users2[j] = records[i].user;
        //         shares2[j] = records[i].shares;
        //         j++;
        //     }
        // }

        // _handleOps(
        //     abi.encodeWithSelector(StakedKinto.batchBurnCurrentPeriodStake.selector, users2, shares2),
        //     payable(_getChainDeployment("StakedKinto"))
        // );

        // require(stakedKinto.balanceOf(records[0].user) == balances[0] - 61455800000000000000, "Did not burn");
        // require(stakedKinto.balanceOf(records[1].user) == balances[1] + 21666666649999900000, "Did not mint");
        // require(
        //     stakedKinto.balanceOf(records[records.length - 1].user) == balances[records.length - 1] - 3036400000000000000,
        //     "Did not burn"
        // );
    }
}
