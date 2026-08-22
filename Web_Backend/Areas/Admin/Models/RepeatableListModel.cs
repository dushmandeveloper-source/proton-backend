namespace Web_Backend.Areas.Admin.Models
{
    // Backs the _RepeatableList partial: a generic "add/remove text rows,
    // serialize to one hidden JSON field on submit" widget used by Course's
    // Content tab for Descriptions/TrainingPoints/Outcomes/Requirements —
    // all four share the same {text, sortOrder} shape.
    public class RepeatableListModel
    {
        public string Title { get; set; } = "";
        public string FieldName { get; set; } = "";
        public string TextField { get; set; } = "";
        public List<RepeatableRow> Items { get; set; } = new();
    }

    public class RepeatableRow
    {
        public string Text { get; }
        public int SortOrder { get; }

        public RepeatableRow(string text, int sortOrder)
        {
            Text = text;
            SortOrder = sortOrder;
        }
    }
}
