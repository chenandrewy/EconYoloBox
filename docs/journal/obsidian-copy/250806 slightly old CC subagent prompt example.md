---
title: slightly old CC subagent prompt example
created: 2025-08-06 08:14:10
tags: []
modified: 2025-08-06, 08:15:50
---
https://www.reddit.com/r/ClaudeAI/comments/1lciedr/cc_agents_are_really_a_cheat_code_prompt_included/

Last two screenshots are from the following prompt/slash command:

You are tasked with conducting a comprehensive security review of task $ARGUMENTS implementation. This is a critical process to ensure the safety and integrity of the implementation/application. Your goal is to identify potential security risks, vulnerabilities, and areas for improvement.

First, familiarize yourself with the task $ARGUMENTS requirements.

Second, do a FULL and THOROUGH security research on the task technology security best practices. Well known security risk in {{TECHNOLOGY}}, things to look out for, industry security best practices etc. using (Web Tool/Context7/Perplexity/Zen) MCP Tool(s).

<security_research> {{ SECURITY_RESEARCH} </security_research>

To conduct this review thoroughly, you will use a parallel subagent approach. You will create at least 5 subagents, each responsible for analyzing different security aspects of the task implementation. Here's how to proceed:

1. Carefully read through the entire task implementation.
    
2. Create at least 5 subagents, assigning each one specific areas to focus on based on the security research. For example:
    
    - Subagent 1: Authentication and authorization
        
    - Subagent 2: Data storage and encryption
        
    - Subagent 3: Network communication
        
    - Subagent 4: Input validation and sanitization
        
    - Subagent 5: Third-party library usage and versioning
        
3. Instruct each subagent to thoroughly analyze their assigned area, looking for potential security risks, code vulnerabilities, and deviations from best practices. They should examine every file and every line of code without exception.
    
4. Have each subagent provide a detailed report of their findings, including:
    
    - Identified security risks or vulnerabilities
        
    - Code snippets or file locations where issues were found
        
    - Explanation of why each issue is a concern
        
    - Recommendations for addressing each issue
        
5. Once all subagents have reported back, carefully analyze and synthesize their findings. Look for patterns, overlapping concerns, and prioritize issues based on their potential impact and severity.
    
6. Prepare a comprehensive security review report with the following sections: a. Executive Summary: A high-level overview of the security review findings b. Methodology: Explanation of the parallel subagent approach and areas of focus c. Findings: Detailed description of each security issue identified, including:
    
    - Issue description
        
    - Affected components or files
        
    - Potential impact
        
    - Risk level (Critical, High, Medium, Low) d. Recommendations: Specific, actionable items to address each identified issue e. Best Practices: Suggestions for improving overall security posture f. Conclusion: Summary of the most critical issues and next steps
        

Your final output should be the security review report, formatted as follows:

<security_review_report> [Insert the comprehensive security review report here, following the structure outlined above] </security_review_report>

**Remember to think critically about the findings from each subagent** and how they interrelate. Your goal is to provide a thorough, actionable report that will significantly improve the security of the task implementation.


