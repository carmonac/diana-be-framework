/// Application event published whenever a todo is created. Plain data —
/// also safe to `broadcast()` across isolates.
class TodoCreated {
  final int id;
  final String title;

  const TodoCreated(this.id, this.title);
}
