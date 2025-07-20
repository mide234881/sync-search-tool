import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

Clarinet.test({
    name: "Sync Search Manager: Create Search Group",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const block = chain.mineBlock([
            Tx.contractCall('sync-search-manager', 'create-search-group', 
                [types.ascii('AI Research Collective')], 
                deployer.address
            )
        ]);

        // First transaction should succeed
        block.receipts[0].result.expectOk();
        block.receipts[0].result.expectUint(1);
    }
}),

Clarinet.test({
    name: "Sync Search Manager: Add Member to Search Group",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const wallet1 = accounts.get('wallet_1')!;

        // First create a search group
        const createGroupBlock = chain.mineBlock([
            Tx.contractCall('sync-search-manager', 'create-search-group', 
                [types.ascii('Research Network')], 
                deployer.address
            )
        ]);

        // Then add a member
        const addMemberBlock = chain.mineBlock([
            Tx.contractCall('sync-search-manager', 'add-member', 
                [types.uint(1), types.principal(wallet1.address)], 
                deployer.address
            )
        ]);

        // Check add member transaction
        addMemberBlock.receipts[0].result.expectOk();
    }
}),

Clarinet.test({
    name: "Sync Search Manager: Create Search Request",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const wallet1 = accounts.get('wallet_1')!;

        // First create a search group
        const createGroupBlock = chain.mineBlock([
            Tx.contractCall('sync-search-manager', 'create-search-group', 
                [types.ascii('Global Research Collective')], 
                deployer.address
            )
        ]);

        // Then add a member
        const addMemberBlock = chain.mineBlock([
            Tx.contractCall('sync-search-manager', 'add-member', 
                [types.uint(1), types.principal(wallet1.address)], 
                deployer.address
            )
        ]);

        // Create a search request
        const createRequestBlock = chain.mineBlock([
            Tx.contractCall('sync-search-manager', 'create-search-request', 
                [
                    types.uint(1),
                    types.ascii('Find cutting-edge machine learning papers'),
                    types.uint(500),
                    types.ascii('priority')
                ], 
                wallet1.address
            )
        ]);

        // Check search request creation
        createRequestBlock.receipts[0].result.expectOk();
        createRequestBlock.receipts[0].result.expectUint(1);
    }
});