---
name: weekly-review
description: Look back on the week. Summarise what was saved in the notebook and which reminders came and went, then ask what to carry over into next week.
tools: [notes.list, notes.search, reminders.list, reminders.create, notes.update]
model: smart
---

# Weekly review

Use this when the user asks for a weekly review, a recap of their week, or help planning next week.
"This week" means the last 7 days unless the user says otherwise.

1. **Gather.**
   - `notes.list` for notebook items created or changed in the last 7 days (notes, ideas, tasks
     and links). Use `notes.search` if the user names a project or topic to focus on.
   - `reminders.list` for reminders that fired, were completed, snoozed or are still upcoming.
2. **Summarise in a short, friendly recap** (under 200 words), grouped like this:
   - **Done:** completed tasks and reminders.
   - **Captured:** new ideas, notes and links, grouped by collection or topic, with a one-line gist.
   - **Still open:** tasks not done, and reminders that were snoozed or missed.
   - **Coming up:** reminders due in the next 7 days.
   Name things the way the user wrote them. Don't invent progress that isn't in the notebook.
3. **Ask what to carry over.** List the open items as a numbered list and ask which ones to keep
   for next week, which to drop, and whether any needs a reminder.
4. **Act only on the answer.**
   - For items to keep with a reminder, create it with `reminders.create` at the time the user
     gives (ask if they don't say).
   - For items to drop, mark the task done with `notes.update` only if the user says it is done;
     otherwise leave it as it is.
5. **Close** with one sentence: what is set for next week.
