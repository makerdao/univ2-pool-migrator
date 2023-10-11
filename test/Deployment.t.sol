// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";

import { UniV2PoolMigratorInit } from "deploy/UniV2PoolMigratorInit.sol";

import { NstDeploy } from "lib/nst/deploy/NstDeploy.sol";
import { NstInit, NstInstance } from "lib/nst/deploy/NstInit.sol";
import { NgtDeploy } from "lib/ngt/deploy/NgtDeploy.sol";
import { NgtInit, NgtInstance } from "lib/ngt/deploy/NgtInit.sol";

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface GemLike {
    function balanceOf(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function approve(address, uint256) external;
}

interface UniV2FactoryLike {
    function createPair(address, address) external returns (address);
}

contract DeploymentTest is DssTest {
    address constant LOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    address constant UNIV2_DAI_MKR_PAIR = 0x517F9dD285e75b599234F7221227339478d0FcC8;
    address constant UNIV2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    address PAUSE_PROXY;
    address DAI;
    address MKR;
    address NST;
    address NGT;
    address UNIV2_NST_NGT_PAIR;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        DssInstance memory dss = MCD.loadFromChainlog(LOG);

        PAUSE_PROXY = ChainlogLike(LOG).getAddress("MCD_PAUSE_PROXY");

        NstInstance memory nstInst = NstDeploy.deploy(address(this), PAUSE_PROXY, ChainlogLike(LOG).getAddress("MCD_JOIN_DAI"));
        NgtInstance memory ngtInst = NgtDeploy.deploy(address(this), PAUSE_PROXY, ChainlogLike(LOG).getAddress("MCD_GOV"), 1200);

        vm.startPrank(PAUSE_PROXY);
        NstInit.init(dss, nstInst);
        NgtInit.init(dss, ngtInst);
        vm.stopPrank();

        DAI = ChainlogLike(LOG).getAddress("MCD_DAI");
        MKR = ChainlogLike(LOG).getAddress("MCD_GOV");
        NST = ChainlogLike(LOG).getAddress("NST");
        NGT = ChainlogLike(LOG).getAddress("NGT");

        UNIV2_NST_NGT_PAIR = UniV2FactoryLike(UNIV2_FACTORY).createPair(NST, NGT);
    }

    function testSetUp() public {
        DssInstance memory dss = MCD.loadFromChainlog(LOG);

        uint256 pProxyDaiMkrBalancePrev = GemLike(UNIV2_DAI_MKR_PAIR).balanceOf(PAUSE_PROXY);
        assertGt(pProxyDaiMkrBalancePrev, 0);
        uint256 pProxyNstNgtBalancePrev = GemLike(UNIV2_NST_NGT_PAIR).balanceOf(PAUSE_PROXY);
        assertEq(pProxyNstNgtBalancePrev, 0);

        uint256 pProxyDaiBalance = GemLike(DAI).balanceOf(UNIV2_DAI_MKR_PAIR) * pProxyDaiMkrBalancePrev / GemLike(UNIV2_DAI_MKR_PAIR).totalSupply();
        uint256 pProxyMkrBalance = GemLike(MKR).balanceOf(UNIV2_DAI_MKR_PAIR) * pProxyDaiMkrBalancePrev / GemLike(UNIV2_DAI_MKR_PAIR).totalSupply();

        vm.startPrank(PAUSE_PROXY);
        UniV2PoolMigratorInit.init(dss, UNIV2_DAI_MKR_PAIR, UNIV2_NST_NGT_PAIR);
        vm.stopPrank();

        uint256 pProxyDaiMkrBalanceAft = GemLike(UNIV2_DAI_MKR_PAIR).balanceOf(PAUSE_PROXY);
        assertEq(pProxyDaiMkrBalanceAft, 0);
        uint256 pProxyNstNgtBalanceAft = GemLike(UNIV2_NST_NGT_PAIR).balanceOf(PAUSE_PROXY);
        assertGt(pProxyNstNgtBalanceAft, 0);
        // 10**3 == UniswapV2Pair MINIMUM_LIQUIDITY => https://github.com/Uniswap/v2-core/blob/ee547b17853e71ed4e0101ccfd52e70d5acded58/contracts/UniswapV2Pair.sol#L121
        assertEq(pProxyNstNgtBalanceAft, GemLike(UNIV2_NST_NGT_PAIR).totalSupply() - 10**3);

        assertEq(GemLike(NST).balanceOf(UNIV2_NST_NGT_PAIR), pProxyDaiBalance);
        assertEq(GemLike(NGT).balanceOf(UNIV2_NST_NGT_PAIR), pProxyMkrBalance * 1200);
    }
}
