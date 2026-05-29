public with sharing class LeadFollowUpBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date cutoffDate = Date.today().addDays(-60);
        return Database.getQueryLocator(
            'SELECT Id, OwnerId FROM Lead WHERE IsConverted = false AND CreatedDate < :cutoffDate'
        );
    }

    public void execute(Database.BatchableContext bc, List<Lead> leads) {
        Date dueDate = Date.today().addDays(2);
        List<Task> tasks = new List<Task>();

        for (Lead lead : leads) {
            tasks.add(new Task(
                Subject      = 'close the lead or mark it as Bogus',
                WhoId        = lead.Id,
                OwnerId      = lead.OwnerId,
                ActivityDate = dueDate,
                Status       = 'Not Started',
                Priority     = 'Normal'
            ));
        }

        if (!tasks.isEmpty()) {
            insert tasks;
        }
    }

    public void finish(Database.BatchableContext bc) {
    }
}
