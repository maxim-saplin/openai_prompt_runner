/// Interface or propmpt metadata storage (SENT, SUCCESS and ERROR statuses),
/// Can come in handy to augment standard logging, e.g. saving prompt statuses to SQL DB
abstract class PromptMetadadataStorage {
  void addPromptSent(DateTime runStartedAt, DateTime promtStartedAt,
      String? runTag, String? tag, String? request);
  void updatePromptSuccess(DateTime runStartedAt, DateTime promtStartedAt,
      int promptTokens, int totalTokens, String? response);
  void updatePromptError(DateTime runStartedAt, DateTime promtStartedAt,
      String? response, int retriesDone);
}
