// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {KintoToken} from "@kinto-core/tokens/KintoToken.sol";
import {VestingContract} from "@kinto-core/tokens/VestingContract.sol";
import {BatchScript} from "forge-safe/BatchScript.sol";

import {Create2Helper} from "@kinto-core-test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "@kinto-core-test/helpers/ArtifactsReader.sol";
import {DeployerHelper} from "@kinto-core-script/utils/DeployerHelper.sol";

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "forge-std/Test.sol";

contract DeployVestingTokensScript is BatchScript, ArtifactsReader, DeployerHelper, Test {
    function run() public {
        if (block.chainid != 1) {
            console.log("This script is meant to be run on the mainnet");
            return;
        }
        // Set the environment variable
        vm.setEnv("CHAIN", "mainnet");
        vm.setEnv("WALLET_TYPE", "ledger");
        vm.setEnv("MNEMONIC_INDEX", "0xc1f4D15C16A1f3555E0a5F7AeFD1e17AD4aaf40B");
        // address panamaSafe = 0x4108162ADC07c627eb575c6e54a00F898c7b3e18;
        // bytes memory data = abi.encodeWithSignature(
        //     "mint(address,uint256)",
        //     _getChainDeployment("VestingContract", 1),
        //     276_000 * 1e18
        // );
        // // Add the encoded transaction to the batch
        // addToBatch(_getChainDeployment("KintoToken", 1), data);
        // executeBatch(panamaSafe, true);
        address mamoriSafe = 0xf152Abda9E4ce8b134eF22Dc3C6aCe19C4895D82;
        KintoToken kintoToken = KintoToken(_getChainDeployment("KintoToken", 1));
        console2.log(kintoToken.balanceOf(_getChainDeployment("VestingContract", 1)));
        _addInvestors();
        _addTeamAdvisors();
        executeBatch(mamoriSafe, true);
    }

    function _addBeneficiaries(
        address[] memory beneficiaries,
        uint256[] memory grantAmounts,
        uint256[] memory startTimestamps,
        uint256[] memory durationSeconds
    ) private {
        // Encode the function call
        bytes memory data = abi.encodeWithSignature(
            "addBeneficiaries(address[],uint256[],uint256[],uint256[])",
            beneficiaries,
            grantAmounts,
            startTimestamps,
            durationSeconds
        );
        // Add the encoded transaction to the batch
        addToBatch(_getChainDeployment("VestingContract", 1), data);
    }

    // 1 year lock from July1st 2024
    function _addInvestors() private {
        // Data from the spreadsheet
        uint256[] memory amounts = new uint256[](41);
        address[] memory beneficiaries = new address[](41);

        // Set start timestamp to July 1st 00:00 UTC 2024
        uint256 startTimestamp = 1719792000; // Unix timestamp for July 1, 2024 00:00:00 UTC

        // Set duration to 365 days in seconds
        uint256 durationSeconds = 365 days;

        // Create arrays for startTimestamps and durations
        uint256[] memory startTimestamps = new uint256[](beneficiaries.length);
        uint256[] memory durations = new uint256[](beneficiaries.length);

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            startTimestamps[i] = startTimestamp;
            durations[i] = durationSeconds;
        }

        // Populate arrays with data (all entries, amounts multiplied by 1e18)
        amounts[0] = 250000 * 1e18;
        amounts[1] = 2500 * 1e18;
        amounts[2] = 6250 * 1e18;
        amounts[3] = 25000 * 1e18;
        amounts[4] = 1250 * 1e18;
        amounts[5] = 6250 * 1e18;
        amounts[6] = 3750 * 1e18;
        amounts[7] = 2500 * 1e18;
        amounts[8] = 1250 * 1e18;
        amounts[9] = 2500 * 1e18;
        amounts[10] = 7500 * 1e18;
        amounts[11] = 22750 * 1e18;
        amounts[12] = 50000 * 1e18;
        amounts[13] = 3750 * 1e18;
        amounts[14] = 50000 * 1e18;
        amounts[15] = 5000 * 1e18;
        amounts[16] = 125000 * 1e18;
        amounts[17] = 6250 * 1e18;
        amounts[18] = 25000 * 1e18;
        amounts[19] = 2500 * 1e18;
        amounts[20] = 500 * 1e18;
        amounts[21] = 387500 * 1e18;
        amounts[22] = 6250 * 1e18;
        amounts[23] = 12500 * 1e18;
        amounts[24] = 25000 * 1e18;
        amounts[25] = 5000 * 1e18;
        amounts[26] = 37500 * 1e18;
        amounts[27] = 6250 * 1e18;
        amounts[28] = 15000 * 1e18;
        amounts[29] = 200000 * 1e18;
        amounts[30] = 12500 * 1e18;
        amounts[31] = 25000 * 1e18;
        amounts[32] = 5000 * 1e18;
        amounts[33] = 5000 * 1e18;
        amounts[34] = 1000 * 1e18;
        amounts[35] = 56250 * 1e18; //alan
        amounts[36] = 165000 * 1e18; //aj
        amounts[37] = 165000 * 1e18; //ak
        amounts[38] = 5000 * 1e18; //fede
        amounts[39] = 250000 * 1e18; //kyber 2
        amounts[40] = 250000 * 1e18; // kyber 3

        beneficiaries[0] = 0xb59A51D0eEa34F3903785fb2e2bab4F752D18008;
        beneficiaries[1] = 0xf0FD3082F54AddD6ef234aF8D3Ffd3F3c66942D0;
        beneficiaries[2] = 0xcfb9b3b97c725a5dB4933f9d5624c94535C9b721;
        beneficiaries[3] = 0x9BC04Ba2f121E3178110B8Be58f64F4f35b622D1;
        beneficiaries[4] = 0x0f5323983F4C12792E78a4B451255D18AB03e41d;
        beneficiaries[5] = 0x01d1e3738222fa955aeAD197313c3Cf19236f411;
        beneficiaries[6] = 0x02cdE0B65C75c19c3e687AeD5DDa241F679398B5;
        beneficiaries[7] = 0x8410373DF6E9b20765c9599c26d585B2cd0Ef628;
        beneficiaries[8] = 0x08E674c4538caE03B6c05405881dDCd95DcaF5a8;
        beneficiaries[9] = 0x5d2815E07Ed95Aea5e4E154C13e0BF89815167a3;
        beneficiaries[10] = 0x346112BCb0819A0fe2a6f1D16217ADE6Ceb49b36;
        beneficiaries[11] = 0xDB06bdBdE4470B3350524CE3FAf7e36e487b53A4;
        beneficiaries[12] = address(1); //set to dummy
        beneficiaries[13] = 0xE08CB49c6D533E2787EC0ff35cd9Eb0ADAD60cbB;
        beneficiaries[14] = 0x6c06923E2B909f3D942dEFd6c4276b53C8B4E462;
        beneficiaries[15] = 0xbB3Cb5Ffc56Ad59cb192333B63C0cfFd745E7D49;
        beneficiaries[16] = 0x62Ba45493B21c890F86A6137592B18B26eb0e6b4;
        beneficiaries[17] = 0xFB5b2DBC66226Ee9E27f5dDcAA4117424068d11c;
        beneficiaries[18] = 0x42Df1Bc3088e164E1DBaE2D877Fb951Bc104Eb8C;
        beneficiaries[19] = 0x1aE72567E6F956A7d9A6376D4916dFFd4E749e27;
        beneficiaries[20] = 0x356705Fd1f38F7f8eC85FA1B2D2B336e559Ef14d;
        beneficiaries[21] = 0xA25ea37C36f724E4C0EE7DD215ff1d3093a1C602;
        beneficiaries[22] = 0x0d24f692c05036602076b3f51242b5A34C55Ee38;
        beneficiaries[23] = 0x47596DD9aF04D0e381053932Dd8Fbf7f97Eb6d49;
        beneficiaries[24] = 0xC9B354464F0827D705940eFA056e29b761A28395;
        beneficiaries[25] = 0xaE0b12Ec2a75F006F7A5729ED897fA80bef6BF25;
        beneficiaries[26] = 0x66EA8aa026Be6ceac085Ba6a389570237CDfa48c;
        beneficiaries[27] = 0x3616a11C20EB35107dB726c7B1592E41433Bc014;
        beneficiaries[28] = 0xFb691B682D6BF85A70a945D05dEcA28496888Ef7;
        beneficiaries[29] = 0x0DC874Fb5260Bd8749e6e98fd95d161b7605774D;
        beneficiaries[30] = 0xCc057a8606dFf785E868631f66ecBAe729A9C5F1;
        beneficiaries[31] = 0x1961D2d97cf7A88Ba8DAFF29D0e51F20c1e4c73e;
        beneficiaries[32] = 0x187c8767D119aB141bBA7E59EFb48A6c0dd6BC74;
        beneficiaries[33] = 0x15587340297A8A2fda40857e58403B91113f6de6;
        beneficiaries[34] = 0xD211AA4552B29f591e89d89e212BC8EEE15135Ac;
        beneficiaries[35] = 0xb4BcFc4A384d44b53BbAf4fF2568846E2E7efb2A;
        beneficiaries[36] = 0x6B1ee65d342067918cC009f7CB933304a280a827;
        beneficiaries[37] = 0x2A6325DB9c9294aDef1123FA85AFdb10f0aba6Dd;
        beneficiaries[38] = 0x2708A58F4Ab71cFD296C8A8d983831e6DffadD67;
        beneficiaries[39] = 0x14951816f149918a5FEC806dEFA9Be550Ef3ecf3;
        beneficiaries[40] = 0xC0568B93a872c29a587c200b160E1d4E851b51C5;

        // log total amount
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        console2.log("Total amount to be vested by investors: ", totalAmount);

        _addBeneficiaries(beneficiaries, amounts, startTimestamps, durations);
    }

    function _addTeamAdvisors() private {
        uint256[] memory amounts = new uint256[](17);
        address[] memory beneficiaries = new address[](17);
        uint256[] memory startTimestamps = new uint256[](17);
        uint256[] memory durations = new uint256[](17);

        // July 1st, 2024 00:00:00 UTC
        uint256 commonStartTimestamp = 1719792000;

        // Populate arrays with data
        (amounts[0], beneficiaries[0], durations[0]) = (
            579500 * 1e18,
            0x848003ba498c36AdF7232b1f1e8c2AbF6d31B017,
            calculateDuration(1688169600, commonStartTimestamp)
        ); // 7/1/2023
        (amounts[1], beneficiaries[1], durations[1]) = (
            579500 * 1e18,
            0x0e157F26E66cA4dB3aE6f81393e581a8880ADeb4,
            calculateDuration(1688169600, commonStartTimestamp)
        ); // 7/1/2023
        (amounts[2], beneficiaries[2], durations[2]) = (
            150000 * 1e18,
            0xb3A91e43Fc97424033fA71fd3a63ecf101424538,
            calculateDuration(1714521600, commonStartTimestamp)
        ); // 5/1/2024
        (amounts[3], beneficiaries[3], durations[3]) = (
            15000 * 1e18,
            0x7D20E87743d92bf1Ff8e6Da28184f22d06a02834,
            calculateDuration(1696204800, commonStartTimestamp)
        ); // 10/2/2023
        (amounts[4], beneficiaries[4], durations[4]) = (
            50000 * 1e18,
            0x5ECE593a2D1724A58Ef179c75C9b4e93e4239E67,
            calculateDuration(1698796800, commonStartTimestamp)
        ); // 11/1/2023
        (amounts[5], beneficiaries[5], durations[5]) = (
            30000 * 1e18,
            0x8b8a9bb77206977742a5bB2fd136e9F580395910,
            calculateDuration(1711065600, commonStartTimestamp)
        ); // 3/21/2024
        (amounts[6], beneficiaries[6], durations[6]) = (
            20000 * 1e18,
            0x04284c8406f1E9c3FF852EE333f8AC69f24A3D3f,
            calculateDuration(1712016000, commonStartTimestamp)
        ); // 4/2/2024
        (amounts[7], beneficiaries[7], durations[7]) = (
            1250 * 1e18, 0xa3cB7E901d10A25bf66B0060013845A26361c04f, calculateDuration(1693267200, commonStartTimestamp)
        ); // 8/29/2023
        (amounts[8], beneficiaries[8], durations[8]) = (
            3750 * 1e18, 0xeAbcD9895F21e3CA87e4D96A84D69fD43d879a7B, calculateDuration(1693267200, commonStartTimestamp)
        ); // 8/29/2023
        (amounts[9], beneficiaries[9], durations[9]) =
            (3750 * 1e18, address(2), calculateDuration(1693872000, commonStartTimestamp)); // 9/5/2023
        (amounts[10], beneficiaries[10], durations[10]) = (
            10000 * 1e18,
            0x77cDC679E06039006e9dfC073EaF995D2208F7cC,
            calculateDuration(1707350400, commonStartTimestamp)
        ); // 2/8/2024
        (amounts[11], beneficiaries[11], durations[11]) = (
            2000 * 1e18, 0x10cCD4136471c7c266a9Fc4569622989Fb4caB99, calculateDuration(1708905600, commonStartTimestamp)
        ); // 2/26/2024
        (amounts[12], beneficiaries[12], durations[12]) = (
            2500 * 1e18, 0x05B478931F983FF0F7783A1cE4940f9a06E2888e, calculateDuration(1706054400, commonStartTimestamp)
        ); // 1/24/2024
        (amounts[13], beneficiaries[13], durations[13]) = (
            2000 * 1e18, 0x51305Da5A03D71De4160b3a5219d1f2c4Cc50be5, calculateDuration(1707955200, commonStartTimestamp)
        ); // 2/15/2024
        (amounts[14], beneficiaries[14], durations[14]) = (
            2000 * 1e18, 0xd689B3E677A5b48e4FD6967D9fEF1e9Bc66A20d0, calculateDuration(1706745600, commonStartTimestamp)
        ); // 2/1/2024
        (amounts[15], beneficiaries[15], durations[15]) = (
            4000 * 1e18, 0xb1Ead992a109ef5720Cc61aaE15c2cD71d827f0c, calculateDuration(1714521600, commonStartTimestamp)
        ); // 4/30/2024
        (amounts[16], beneficiaries[16], durations[16]) = (
            50000 * 1e18,
            0x2E336836Cf0365E899bD511170A7fA57f05E2D9D,
            calculateDuration(1714521600, commonStartTimestamp)
        ); // 5/1/2024

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            startTimestamps[i] = commonStartTimestamp;
        }
        // log total amount
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        console2.log("Total amount to be vested by team: ", totalAmount);

        _addBeneficiaries(beneficiaries, amounts, startTimestamps, durations);
    }

    function calculateDuration(uint256 originalStartTimestamp, uint256 newStartTimestamp)
        internal
        pure
        returns (uint256)
    {
        if (originalStartTimestamp >= newStartTimestamp) {
            return 4 * 365 days; // Full 4 years if original start is after or equal to new start
        }
        uint256 timeElapsed = newStartTimestamp - originalStartTimestamp;
        if (timeElapsed >= 4 * 365 days) {
            return 0; // No time left if more than 4 years have passed
        }
        return (4 * 365 days) - timeElapsed; // Remaining time until 4 years from original start
    }
}
