const String promptsTable = '''
CREATE TABLE 
  prompts (
    run_started_at DATETIME not null default CURRENT_TIMESTAMP,
    prompt_sent_at DATETIME not null,
    prompt_updated_at DATETIME not null,
    run_tag TEXT null,
    tag TEXT null,
    status TEXT not null,
    tokens_sent INTEGER NULL,
    total_tokens INTEGER NULL, 
    primary key (run_started_at, prompt_sent_at)
  )
''';
