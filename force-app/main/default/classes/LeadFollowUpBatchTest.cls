@IsTest
private class LeadFollowUpBatchTest {

    // ── helpers ──────────────────────────────────────────────────────────────

    private static Lead makeLeadRecord(String lastName) {
        return new Lead(
            FirstName = 'Test',
            LastName  = lastName,
            Company   = 'Test Company',
            Status    = 'Open - Not Contacted'
        );
    }

    // ── tests ─────────────────────────────────────────────────────────────────

    @IsTest
    static void testTasksCreatedForOldLeads() {
        // 3 leads older than 60 days → expect 3 tasks
        List<Lead> oldLeads = new List<Lead>{
            makeLeadRecord('OldOne'),
            makeLeadRecord('OldTwo'),
            makeLeadRecord('OldThree')
        };
        insert oldLeads;

        DateTime past = DateTime.now().addDays(-61);
        for (Lead l : oldLeads) {
            Test.setCreatedDate(l.Id, past);
        }

        Test.startTest();
        Database.executeBatch(new LeadFollowUpBatch(), 200);
        Test.stopTest();

        List<Task> tasks = [SELECT Id, Subject, OwnerId, ActivityDate, Status, WhoId FROM Task];
        Assert.areEqual(3, tasks.size(), 'Expected one task per old lead');

        Task t = tasks[0];
        Assert.areEqual('close the lead or mark it as Bogus', t.Subject, 'Wrong subject');
        Assert.areEqual(Date.today().addDays(2), t.ActivityDate, 'Due date should be today + 2 days');
        Assert.areEqual('Not Started', t.Status, 'Task status mismatch');
    }

    @IsTest
    static void testTaskOwnerMatchesLeadOwner() {
        Lead lead = makeLeadRecord('OwnerCheck');
        insert lead;
        Test.setCreatedDate(lead.Id, DateTime.now().addDays(-61));

        Test.startTest();
        Database.executeBatch(new LeadFollowUpBatch(), 200);
        Test.stopTest();

        Task t = [SELECT OwnerId, WhoId FROM Task LIMIT 1];
        Lead inserted = [SELECT OwnerId FROM Lead WHERE Id = :lead.Id];
        Assert.areEqual(inserted.OwnerId, t.OwnerId, 'Task owner should match lead owner');
        Assert.areEqual(lead.Id, t.WhoId, 'Task WhoId should point to the lead');
    }

    @IsTest
    static void testRecentLeadsExcluded() {
        // Lead created today → should NOT receive a task
        Lead recentLead = makeLeadRecord('RecentLead');
        insert recentLead;
        // No Test.setCreatedDate → CreatedDate is today (within 60 days)

        Test.startTest();
        Database.executeBatch(new LeadFollowUpBatch(), 200);
        Test.stopTest();

        List<Task> tasks = [SELECT Id FROM Task WHERE WhoId = :recentLead.Id];
        Assert.areEqual(0, tasks.size(), 'Recent lead should not receive a task');
    }

    @IsTest
    static void testConvertedLeadsExcluded() {
        // Only unconverted leads should be picked up; converted ones must be skipped.
        // We verify by having only a backdated converted lead → zero tasks.
        Lead lead = makeLeadRecord('ConvertedLead');
        insert lead;
        Test.setCreatedDate(lead.Id, DateTime.now().addDays(-61));

        // Convert the lead
        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(lead.Id);
        lc.setConvertedStatus([SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1].MasterLabel);
        lc.setDoNotCreateOpportunity(true);
        Database.convertLead(lc);

        Test.startTest();
        Database.executeBatch(new LeadFollowUpBatch(), 200);
        Test.stopTest();

        List<Task> tasks = [SELECT Id FROM Task WHERE WhoId = :lead.Id];
        Assert.areEqual(0, tasks.size(), 'Converted lead should not receive a task');
    }

    @IsTest
    static void testNoLeadsNoError() {
        // Running batch against an empty org should not throw any exception
        Test.startTest();
        Database.executeBatch(new LeadFollowUpBatch(), 200);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Task], 'No tasks should exist when there are no qualifying leads');
    }
}
