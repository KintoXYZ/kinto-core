pragma solidity ^0.8.24;

import {CVR} from "@kinto-core/vaults/CVR.sol";

import {Create2Helper} from "@kinto-core-test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "@kinto-core-test/helpers/ArtifactsReader.sol";
import {DeployerHelper} from "@kinto-core-script/utils/DeployerHelper.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

contract DeployCVRScript is Create2Helper, ArtifactsReader, DeployerHelper, Test {
    function run() public {
        if (block.chainid != 1) {
            console.log("This script is meant to be run on the mainnet");
            return;
        }
        vm.broadcast();
        CVR cvr = new CVR({});

        // Checks
        assertEq(address(cvr.USDC()), 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        assertEq(cvr.OWNER(), 0x2E7111Ef34D39b36EC84C656b947CA746e495Ff6);

        // address[] memory users = new address[](152);
        // uint256[] memory amounts = new uint256[](152);
        // users[0] = 0x5AbdC1F01cd677e8aCF2EC8cEe061bfC2036f985;
        // users[1] = 0xEc8A675289BEb9cbEDBE5E8c91059668E2192Df8;
        // users[2] = 0xe8C8eA20A7c47DD979947F1a6229Ff9AC68fEBD3;
        // users[3] = 0x97ac82E52a423eD5Cc8084Ba1b056F716124C28D;
        // users[4] = 0x0AF5647b4655Fea79a3cbf4A4aaaAf94bb8a0E87;
        // users[5] = 0xb7f9d7f207A1f0B04aCdD40DD162BFDD9b442788;
        // users[6] = 0xD7452A9b513c7D0C98144132Aa1DB8e9CA0224c9;
        // users[7] = 0xD3eE42a68F678b0b6b133d4fE2FF3b600C3f0672;
        // users[8] = 0x8ebb539b645A7053D3f5c149cbe0F7045dF2A1D5;
        // users[9] = 0xEeebdeAEC2C87Ee38fA8AA3a148F49a87990d30c;
        // users[10] = 0x2a46EBc0D3cD522de2561ae1F903e228B92B64E8;
        // users[11] = 0x50Da33142CdD903Af82666Df5D4149dc6aB0c59d;
        // users[12] = 0x2f76851a0EB64B80FE3610A5259770F3FDeCd5EC;
        // users[13] = 0xE725f07Ba64E5110c34Ba9F8a58196986A698BC2;
        // users[14] = 0x17061B7473bFB1442177306496547282F34Ad7cF;
        // users[15] = 0x1C12E6Ea7b906BFb15F3f4F83fc453D94575Dc6f;
        // users[16] = 0x702094a1AC85a4AE93940F92D672754910310238;
        // users[17] = 0x191B86bc5631A5e91CEf723375e159Af2B6aF558;
        // users[18] = 0x50d4Df2878e44F0D4BA02502f0a3646f9daf5d5f;
        // users[19] = 0xadbcf19fA09F8ebb5eDA65A442e6621E5b1B36a8;
        // users[20] = 0xa3829dDaA6Cf65d89562ab52B0011c63e961702A;
        // users[21] = 0xAF136B2307B4e560f4BA7ff16283F12C21367453;
        // users[22] = 0xdd5D15dB48B7ddb92B53e5d4490B64C10133B95a;
        // users[23] = 0x2E71F6147B1f28C2B9cCC2d4a566b86B7A52298E;
        // users[24] = 0x5c3a15C2478F777C48138d1d3bf6EfAe628BDc51;
        // users[25] = 0x4FAD230233e571EdBAf1CF9ab38d8A957da93a02;
        // users[26] = 0x7B45fAE0991c87dCf0A821a038C3cea9560c4c95;
        // users[27] = 0xDbb6c32c5cC886F95bBa73c9C891799F4d767046;
        // users[28] = 0x6f4E8096e4fa46AF0534db16708910008040e566;
        // users[29] = 0xF138984Bd659edd8DE38fb2FebEdae8bED5E0255;
        // users[30] = 0xF9dBd0d9Da81B6C1Fb3b5D4C9773b3e905ED05a6;
        // users[31] = 0xc002DFb052990473751AbD2FDB938795a88E8025;
        // users[32] = 0xf4e7E6B600286fFba8154F5125420A0F78DB835d;
        // users[33] = 0x9B2607Cc03b0147A276Ae7C2b97A25fBd67BD48f;
        // users[34] = 0x24cf0419330ED82a84Bf4cFd79dA7dc311118bBD;
        // users[35] = 0x9CE8986e745b7aDd139a1369383592A102d5902f;
        // users[36] = 0x6A0B45E151D68188E8e8c258A951Ef2afbdB8c9C;
        // users[37] = 0x463bFa3f6Dfa2FE59e215B59e90C0c86716d721B;
        // users[38] = 0x189c00c32f98f2312F05521ea15eD6fb7d05D33d;
        // users[39] = 0xF575Dbef3CC95A23B6D49F7D83aa135C6446e927;
        // users[40] = 0x261caF2428A703477Ee78f0b0f653ccEB0c05601;
        // users[41] = 0xeFAd0d64546c5bf9019b5815f68535488d025C61;
        // users[42] = 0x8a75F44a5310F44BE06cf0e7FDB7e7881484b191;
        // users[43] = 0x2C0BABeEc0bcD38E2b99bfe9d6e6226db4cBa35b;
        // users[44] = 0x2FEdF16560F527fEC5f1cCA6dF0a4EC180408Ce9;
        // users[45] = 0xe5C7B4166d5cFaa9cAE93048cf683F870Ad4faEb;
        // users[46] = 0xCE9fe9b2B60AB847A09d33b272D03F50e60ab99b;
        // users[47] = 0xc03A67148057118c74162bD7372AacD60a2e70F0;
        // users[48] = 0x36Fa11f6715A5E440871F531030Ee4E94d7B9309;
        // users[49] = 0x21bf5fb186D790C5727Fd462050A8D380f730a49;
        // users[50] = 0xc985D483f0D70b578b9dC4197C0C2E623Cc5DDAd;
        // users[51] = 0xe38B3806517671C470c2F2c389715f0442a36295;
        // users[52] = 0xf1f57B31a953f8e481C5c8f52fe38600268dBa14;
        // users[53] = 0x3b30d44dF9Afffc07A51457E18410c4ca0F90896;
        // users[54] = 0x711382EBBf8E25f782f5861E7E87fC8E66f1bcE1;
        // users[55] = 0x7Cfe310b31C71C45a8141326Cb73F7e248a42bd1;
        // users[56] = 0x655fd4FBF15a6a636bD1c483C3d49fd9da7e8CE8;
        // users[57] = 0x820F864e64051DE7c621C3d33C7B78C576b3d361;
        // users[58] = 0x115bBf252ad769b8e35AA4B100ca91bA501C8eDb;
        // users[59] = 0xCDFCb06D537F2513c99eaa3B33F9eA6e0D4311Ab;
        // users[60] = 0xDDe4Ad09bdd30B44B9cCDDea6c067Fff572fAd55;
        // users[61] = 0x7533ec3D5cb0c6077ca80106766c001B642cE82d;
        // users[62] = 0xB7828e0f8C1eEe6a278AD1B0704a8dF170EcD481;
        // users[63] = 0xd415b06677A95aFaEf02764BB4C88219B4B64871;
        // users[64] = 0x04024b3c2dd5dff7782b23dA64Cc3D7FeDdD99dd;
        // users[65] = 0x012E868121DB86b3dAc062F58cdC797c8879Ce7E;
        // users[66] = 0x5D79a45ADE9F88eD694CAee7a28C03db66b519C8;
        // users[67] = 0xB7828e0f8C1eEe6a278AD1B0704a8dF170EcD481;
        // users[68] = 0xC71deD6f0E5660DFe79C849058Afd9BE7a3c85b8;
        // users[69] = 0x492e8D9bC914C75Df7DE91a2cA5416fdFDF7596f;
        // users[70] = 0xB1A0B8D25308977B61f71D2D83Dce851a463Efb6;
        // users[71] = 0x267e54fE02400Fe24Be97A05D4F8D24e4b8B9E25;
        // users[72] = 0xe9F3cB25642616866F27A954115114C16e9451A3;
        // users[73] = 0x72f82737e883709b5c87DaDF0ebA21f7B27A69e1;
        // users[74] = 0xD9e7C96bEFA5084b9fBDD8C815E135fAFfb132a7;
        // users[75] = 0xDDBFfe114940b433076324Af6B181685ba1E933d;
        // users[76] = 0xC104F44c5E87bC7f75E4c17F60d18276FCc3A943;
        // users[77] = 0xDbA93411f045b9637ff3dB260d00e7623AA8d2Ab;
        // users[78] = 0xB18C38D991cC55FAfE13180f64FAB270a1Ede29e;
        // users[79] = 0x755a883a97834007379b42C5565a41b8E267ceb0;
        // users[80] = 0xcB06bEDe7cB0a4b333581B6BdcD05f7cc737b9cC;
        // users[81] = 0xCA248AfBcC09E474EcfbEe249bA89f90db32cb5a;
        // users[82] = 0xa06721B4013F0dF4236b2B64361010C5eD12e1d4;
        // users[83] = 0xa1C9d41719c4fFD99463F1CfA579d9b6A96b50c6;
        // users[84] = 0x4f7A246A84EfF713CB88363BE8d7D8f95306aFDb;
        // users[85] = 0xCdfB243DAFC44B7AD776349CEbb335B78204c419;
        // users[86] = 0x58e4e9D30Da309624c785069A99709b16276B196;
        // users[87] = 0xf71F56b6e61E96B4b63Da49910Ce4a404537137f;
        // users[88] = 0x3EFd1fA3D4e5784648adF7396C3478999ec90249;
        // users[89] = 0xdF238F5161B7efD526efd8067086cAd7497f3b52;
        // users[90] = 0x4F5FC247BDff01Fde2806e2A089Ac7dAabc45691;
        // users[91] = 0xD1e219218f14CCEa325b520fa41f3FA78a955B01;
        // users[92] = 0xaef4BAA66318f4821402998272678274b6123fcC;
        // users[93] = 0xF64db6d105C7deA5A40C22593631DE99a837Db1e;
        // users[94] = 0x0b89d72ba572b1389C444583F6dB62a36Af0029c;
        // users[95] = 0x47596DD9aF04D0e381053932Dd8Fbf7f97Eb6d49;
        // users[96] = 0xc4293f52633B3603E65e9B4C2b4Df40eEeCcA91c;
        // users[97] = 0x7FE4b2632f5AE6d930677D662AF26Bc0a06672b3;
        // users[98] = 0xf54f65FB852dAe5A440d5617006f7aDE104bC76E;
        // users[99] = 0xe8D5EE67A69394E721cdF2481f633C37aC70aB91;
        // users[100] = 0x72f82737e883709b5c87DaDF0ebA21f7B27A69e1;
        // users[101] = 0x3367A005c2bEf54f2836a616ce3E4Fa2d35910da;
        // users[102] = 0x3367A005c2bEf54f2836a616ce3E4Fa2d35910da;
        // users[103] = 0xfFBB310F6f4Eb567b2C239794E6CCEc2fc43503A;
        // users[104] = 0xaEdF0F57AFCA7BC2E3DA5A8399feC7ed4BD3da92;
        // users[105] = 0x8c071860b028aF43E800d36806155c6dB6Cf8d4A;
        // users[106] = 0x2B7eB65B0f55eee19BfF5A66FBa989aE0118Fb12;
        // users[107] = 0x660ad4B5A74130a4796B4d54BC6750Ae93C86e6c;
        // users[108] = 0xfFBB310F6f4Eb567b2C239794E6CCEc2fc43503A;
        // users[109] = 0x3367A005c2bEf54f2836a616ce3E4Fa2d35910da;
        // users[110] = 0xA9475Bb40a256E0636B5b5aB3d4E0163C2A5D5fA;
        // users[111] = 0xB7828e0f8C1eEe6a278AD1B0704a8dF170EcD481;
        // users[112] = 0x7464d5B3Cfb00Ff6Fe5919A7e5ba177d9E1AAAC3;
        // users[113] = 0xA9475Bb40a256E0636B5b5aB3d4E0163C2A5D5fA;
        // users[114] = 0x0cf32019241b61DFE4247c61534Ec80c51389E6b;
        // users[115] = 0xA553d6417EF23af0D62E8296f88c9dad50F13a30;
        // users[116] = 0xA9475Bb40a256E0636B5b5aB3d4E0163C2A5D5fA;
        // users[117] = 0x05D621A053E51ebBC7e445cd9FCC533c72ff5385;
        // users[118] = 0x2C10c78fDE5837C1beFa6e6e6c6633CD0F1bDA05;
        // users[119] = 0x3367A005c2bEf54f2836a616ce3E4Fa2d35910da;
        // users[120] = 0xA9475Bb40a256E0636B5b5aB3d4E0163C2A5D5fA;
        // users[121] = 0x7464d5B3Cfb00Ff6Fe5919A7e5ba177d9E1AAAC3;
        // users[122] = 0xA553d6417EF23af0D62E8296f88c9dad50F13a30;
        // users[123] = 0xB7828e0f8C1eEe6a278AD1B0704a8dF170EcD481;
        // users[124] = 0xC923a792aCC3080e945b9E1479Cac75A5Fc97499;
        // users[125] = 0xE7Ba5C00A170B075323C0fab1445dB0Ba8c65984;
        // users[126] = 0xf54f65FB852dAe5A440d5617006f7aDE104bC76E;
        // users[127] = 0xf54f65FB852dAe5A440d5617006f7aDE104bC76E;
        // users[128] = 0xf54f65FB852dAe5A440d5617006f7aDE104bC76E;
        // users[129] = 0xf54f65FB852dAe5A440d5617006f7aDE104bC76E;
        // users[130] = 0xf54f65FB852dAe5A440d5617006f7aDE104bC76E;
        // users[131] = 0xC923a792aCC3080e945b9E1479Cac75A5Fc97499;
        // users[132] = 0xA9475Bb40a256E0636B5b5aB3d4E0163C2A5D5fA;
        // users[133] = 0x0cf32019241b61DFE4247c61534Ec80c51389E6b;
        // users[134] = 0xA553d6417EF23af0D62E8296f88c9dad50F13a30;
        // users[135] = 0x7a23B628cdE174f82175C1fE67D8755C0C7f400C;
        // users[136] = 0xA9475Bb40a256E0636B5b5aB3d4E0163C2A5D5fA;
        // users[137] = 0x189FF43656c2eE65D6b52F0e4793bF143fB989E0;
        // users[138] = 0x1c2DcD412fcDA006E61306D77CEb24D7E5129710;
        // users[139] = 0xA9475Bb40a256E0636B5b5aB3d4E0163C2A5D5fA;
        // users[140] = 0x7464d5B3Cfb00Ff6Fe5919A7e5ba177d9E1AAAC3;
        // users[141] = 0xA553d6417EF23af0D62E8296f88c9dad50F13a30;
        // users[142] = 0xB7828e0f8C1eEe6a278AD1B0704a8dF170EcD481;
        // users[143] = 0xA9475Bb40a256E0636B5b5aB3d4E0163C2A5D5fA;
        // users[144] = 0xE7Ba5C00A170B075323C0fab1445dB0Ba8c65984;
        // users[145] = 0x0cf32019241b61DFE4247c61534Ec80c51389E6b;
        // users[146] = 0xA553d6417EF23af0D62E8296f88c9dad50F13a30;
        // users[147] = 0x6DC8501f9AE2b5aEF6B104d7fed6128B292DEBAF;
        // users[148] = 0x2C10c78fDE5837C1beFa6e6e6c6633CD0F1bDA05;
        // users[149] = 0xA9475Bb40a256E0636B5b5aB3d4E0163C2A5D5fA;
        // users[150] = 0xA553d6417EF23af0D62E8296f88c9dad50F13a30;
        // users[151] = 0x0cf32019241b61DFE4247c61534Ec80c51389E6b;

        // // Duplicated addresses in users array (intentional):
        // // 0x3367A005c2bEf54f2836a616ce3E4Fa2d35910da appears at: [101, 102, 109, 119]
        // // 0xfFBB310F6f4Eb567b2C239794E6CCEc2fc43503A appears at: [103, 108]
        // // 0xA9475Bb40a256E0636B5b5aB3d4E0163C2A5D5fA appears at: [110, 113, 116, 120, 132, 136, 139, 143, 149]
        // // 0x7464d5B3Cfb00Ff6Fe5919A7e5ba177d9E1AAAC3 appears at: [112, 121, 140]
        // // 0xA553d6417EF23af0D62E8296f88c9dad50F13a30 appears at: [115, 122, 134, 141, 146, 150]
        // // 0xB7828e0f8C1eEe6a278AD1B0704a8dF170EcD481 appears at: [111, 123, 142]
        // // 0xC923a792aCC3080e945b9E1479Cac75A5Fc97499 appears at: [124, 131]
        // // 0xf54f65FB852dAe5A440d5617006f7aDE104bC76E appears at: [98, 126, 127, 128, 129, 130]
        // // 0xE7Ba5C00A170B075323C0fab1445dB0Ba8c65984 appears at: [125, 144]
        // // 0x0cf32019241b61DFE4247c61534Ec80c51389E6b appears at: [114, 133, 145, 151]
        // // 0x2C10c78fDE5837C1beFa6e6e6c6633CD0F1bDA05 appears at: [118, 148]

        // amounts[0] = 10013;
        // amounts[1] = 18206;
        // amounts[2] = 29039;
        // amounts[3] = 49236;
        // amounts[4] = 77367;
        // amounts[5] = 78953;
        // amounts[6] = 96035;
        // amounts[7] = 108584;
        // amounts[8] = 728588;
        // amounts[9] = 20026062;
        // amounts[10] = 20573065;
        // amounts[11] = 20596858;
        // amounts[12] = 21518027;
        // amounts[13] = 21908857;
        // amounts[14] = 24031263;
        // amounts[15] = 24031278;
        // amounts[16] = 24288503;
        // amounts[17] = 25032604;
        // amounts[18] = 25913522;
        // amounts[19] = 27475744;
        // amounts[20] = 27567713;
        // amounts[21] = 31116763;
        // amounts[22] = 35045647;
        // amounts[23] = 38560252;
        // amounts[24] = 38760345;
        // amounts[25] = 41714332;
        // amounts[26] = 45317323;
        // amounts[27] = 47650049;
        // amounts[28] = 50017619;
        // amounts[29] = 50065384;
        // amounts[30] = 55120415;
        // amounts[31] = 55645776;
        // amounts[32] = 69087802;
        // amounts[33] = 69955464;
        // amounts[34] = 70016404;
        // amounts[35] = 73693139;
        // amounts[36] = 74000585;
        // amounts[37] = 74762043;
        // amounts[38] = 75022843;
        // amounts[39] = 78701687;
        // amounts[40] = 79300613;
        // amounts[41] = 86451794;
        // amounts[42] = 87632339;
        // amounts[43] = 100023980;
        // amounts[44] = 100130028;
        // amounts[45] = 108542488;
        // amounts[46] = 111600770;
        // amounts[47] = 115148637;
        // amounts[48] = 120029434;
        // amounts[49] = 122159114;
        // amounts[50] = 125113150;
        // amounts[51] = 129583881;
        // amounts[52] = 178242377;
        // amounts[53] = 180235012;
        // amounts[54] = 180838372;
        // amounts[55] = 190247803;
        // amounts[56] = 196658679;
        // amounts[57] = 200078224;
        // amounts[58] = 200243703;
        // amounts[59] = 200534374;
        // amounts[60] = 205352383;
        // amounts[61] = 254331369;
        // amounts[62] = 297714109;
        // amounts[63] = 300293425;
        // amounts[64] = 300380957;
        // amounts[65] = 319662636;
        // amounts[66] = 331848493;
        // amounts[67] = 333766326;
        // amounts[68] = 380601053;
        // amounts[69] = 400038614;
        // amounts[70] = 400519485;
        // amounts[71] = 500622394;
        // amounts[72] = 500652863;
        // amounts[73] = 650024696;
        // amounts[74] = 1001160203;
        // amounts[75] = 1001305597;
        // amounts[76] = 1105339179;
        // amounts[77] = 1345232185;
        // amounts[78] = 1686115605;
        // amounts[79] = 1828317279;
        // amounts[80] = 2183998967;
        // amounts[81] = 2435669195;
        // amounts[82] = 2780166774;
        // amounts[83] = 3326455795;
        // amounts[84] = 3331550277;
        // amounts[85] = 3696102959;
        // amounts[86] = 3700197019;
        // amounts[87] = 4035971465;
        // amounts[88] = 6511589044;
        // amounts[89] = 10107049850;
        // amounts[90] = 11127714742;
        // amounts[91] = 12292335352;
        // amounts[92] = 12337789731;
        // amounts[93] = 17006421148;
        // amounts[94] = 70014841152;
        // amounts[95] = 392295347480;
        // amounts[96] = 504146424695;
        // amounts[97] = 1001304233274;
        // amounts[98] = 0; // 0xf54f65FB852dAe5A440d5617006f7aDE104bC76E (consolidated to [130])
        // amounts[99] = 256882;
        // amounts[100] = 405556;
        // amounts[101] = 0; // 0x3367A005c2bEf54f2836a616ce3E4Fa2d35910da (consolidated to [119])
        // amounts[102] = 0; // 0x3367A005c2bEf54f2836a616ce3E4Fa2d35910da (consolidated to [119])
        // amounts[103] = 0; // 0xfFBB310F6f4Eb567b2C239794E6CCEc2fc43503A (consolidated to [108])
        // amounts[104] = 10000000;
        // amounts[105] = 10883540;
        // amounts[106] = 20000000;
        // amounts[107] = 20000000;
        // amounts[108] = 25059692; // 0xfFBB310F6f4Eb567b2C239794E6CCEc2fc43503A (5000000 + 20059692)
        // amounts[109] = 0; // 0x3367A005c2bEf54f2836a616ce3E4Fa2d35910da (consolidated to [119])
        // amounts[110] = 0; // 0xA9475Bb40a256E0636B5b5aB3d4E0163C2A5D5fA (consolidated to [149])
        // amounts[111] = 0; // 0xB7828e0f8C1eEe6a278AD1B0704a8dF170EcD481 (consolidated to [142])
        // amounts[112] = 0; // 0x7464d5B3Cfb00Ff6Fe5919A7e5ba177d9E1AAAC3 (consolidated to [140])
        // amounts[113] = 0; // 0xA9475Bb40a256E0636B5b5aB3d4E0163C2A5D5fA (consolidated to [149])
        // amounts[114] = 0; // 0x0cf32019241b61DFE4247c61534Ec80c51389E6b (consolidated to [151])
        // amounts[115] = 0; // 0xA553d6417EF23af0D62E8296f88c9dad50F13a30 (consolidated to [150])
        // amounts[116] = 0; // 0xA9475Bb40a256E0636B5b5aB3d4E0163C2A5D5fA (consolidated to [149])
        // amounts[117] = 310000000;
        // amounts[118] = 0; // 0x2C10c78fDE5837C1beFa6e6e6c6633CD0F1bDA05 (consolidated to [148])
        // amounts[119] = 540000000; // 0x3367A005c2bEf54f2836a616ce3E4Fa2d35910da (1000000 + 1340000 + 25700000 + 504000000)
        // amounts[120] = 0; // 0xA9475Bb40a256E0636B5b5aB3d4E0163C2A5D5fA (consolidated to [149])
        // amounts[121] = 0; // 0x7464d5B3Cfb00Ff6Fe5919A7e5ba177d9E1AAAC3 (consolidated to [140])
        // amounts[122] = 0; // 0xA553d6417EF23af0D62E8296f88c9dad50F13a30 (consolidated to [150])
        // amounts[123] = 0; // 0xB7828e0f8C1eEe6a278AD1B0704a8dF170EcD481 (consolidated to [142])
        // amounts[124] = 0; // 0xC923a792aCC3080e945b9E1479Cac75A5Fc97499 (consolidated to [131])
        // amounts[125] = 0; // 0xE7Ba5C00A170B075323C0fab1445dB0Ba8c65984 (consolidated to [144])
        // amounts[126] = 0; // 0xf54f65FB852dAe5A440d5617006f7aDE104bC76E (consolidated to [130])
        // amounts[127] = 0; // 0xf54f65FB852dAe5A440d5617006f7aDE104bC76E (consolidated to [130])
        // amounts[128] = 0; // 0xf54f65FB852dAe5A440d5617006f7aDE104bC76E (consolidated to [130])
        // amounts[129] = 0; // 0xf54f65FB852dAe5A440d5617006f7aDE104bC76E (consolidated to [130])
        // amounts[130] = 7400000013; // 0xf54f65FB852dAe5A440d5617006f7aDE104bC76E (13 + 1236081056 + 1236169791 + 1236174638 + 1236973744 + 1251853538)
        // amounts[131] = 2427079309; // 0xC923a792aCC3080e945b9E1479Cac75A5Fc97499 (1083671831 + 1343399478)
        // amounts[132] = 0; // 0xA9475Bb40a256E0636B5b5aB3d4E0163C2A5D5fA (consolidated to [149])
        // amounts[133] = 0; // 0x0cf32019241b61DFE4247c61534Ec80c51389E6b (consolidated to [151])
        // amounts[134] = 0; // 0xA553d6417EF23af0D62E8296f88c9dad50F13a30 (consolidated to [150])
        // amounts[135] = 2877320000;
        // amounts[136] = 0; // 0xA9475Bb40a256E0636B5b5aB3d4E0163C2A5D5fA (consolidated to [149])
        // amounts[137] = 5001000000;
        // amounts[138] = 8773687989;
        // amounts[139] = 0; // 0xA9475Bb40a256E0636B5b5aB3d4E0163C2A5D5fA (consolidated to [149])
        // amounts[140] = 20430489964; // 0x7464d5B3Cfb00Ff6Fe5919A7e5ba177d9E1AAAC3 (52018809 + 1020746456 + 20029741798)
        // amounts[141] = 0; // 0xA553d6417EF23af0D62E8296f88c9dad50F13a30 (consolidated to [150])
        // amounts[142] = 39047274278; // 0xB7828e0f8C1eEe6a278AD1B0704a8dF170EcD481 (38180471 + 1044939207 + 28598336209)
        // amounts[143] = 0; // 0xA9475Bb40a256E0636B5b5aB3d4E0163C2A5D5fA (consolidated to [149])
        // amounts[144] = 31670339789; // 0xE7Ba5C00A170B075323C0fab1445dB0Ba8c65984 (1116395573 + 30553984116)
        // amounts[145] = 0; // 0x0cf32019241b61DFE4247c61534Ec80c51389E6b (consolidated to [151])
        // amounts[146] = 0; // 0xA553d6417EF23af0D62E8296f88c9dad50F13a30 (consolidated to [150])
        // amounts[147] = 46462676749;
        // amounts[148] = 50020465500; // 0x2C10c78fDE5837C1beFa6e6e6c6633CD0F1bDA05 (500000000 + 49520465500)
        // amounts[149] = 125000000000; // 0xA9475Bb40a256E0636B5b5aB3d4E0163C2A5D5fA (25978502 + 77938322 + 200000007 + 509766834 + 1529355769 + 4000000152 + 10002971856 + 30010000000 + 80000003043)
        // amounts[150] = 137434532604; // 0xA553d6417EF23af0D62E8296f88c9dad50F13a30 (100000000 + 1023351025 + 1754858873 + 20080850307 + 34434966579 + 100000000000)
        // amounts[151] = 645225115124; // 0x0cf32019241b61DFE4247c61534Ec80c51389E6b (78722511 + 1574450234 + 31489004690 + 629780093807)

        // cvr.setUsersDonationInfo(users, amounts);

        // (uint256 amt, bool claimed) = cvr.founderDonations(0x5AbdC1F01cd677e8aCF2EC8cEe061bfC2036f985);
        // assertEq(amt, 10013 * 1e6);
        // (amt, claimed) = cvr.founderDonations(0x0cf32019241b61DFE4247c61534Ec80c51389E6b);
        // assertEq(amt, 645225115124);

        saveContractAddress("CVR", address(cvr));
    }
}
