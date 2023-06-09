Provides `PromptRunner` which streamlines mass execution of prompts against OpenAI or Azure GPT chat endpoints. Example use-case:  dataset classification via LLM. 

You start by planning how many iterations you would like to make (iteration count) and providing a callback that is called in each iteration. In the callback you provide the prompt as well as get future that gets called upon prompt completion.

Features:
- Starting at given iteration (e.g. when you need to resume)
- Parallel API calls, rotating API keys (e.g. Azure has 2 API keys per deployment)
- Error handling and retries (e.g. timeouts of throttling from endpoints)
- Logging all prompts to text files, each PromptRunner.run() create a folder under /logs directory
- Azure or OpenAI endpoints can be used
