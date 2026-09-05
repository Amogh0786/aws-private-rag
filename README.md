# 🔐 Secure Enterprise AI Assistant

Welcome to your new internal AI Assistant! 

This tool allows you to ask questions and get instant, accurate answers based entirely on our company's private documents, policies, and knowledge base.

## 🌟 Why Use This Tool?
* **Instant Answers:** No more digging through hundreds of PDF pages or internal wikis to find the exact paragraph you need. Just ask a question.
* **100% Private & Secure:** This is **not** a public AI tool. Your questions, the company's documents, and the AI's answers **never leave our highly secure internal network**. Nothing is sent over the public internet, and your data is never used to train public AI models.
* **Highly Accurate:** We have strictly instructed this AI to only answer based on the provided company documents. If it doesn't know the answer, it will tell you, rather than making something up (hallucinating).

## 🚀 How to Use It
1. **Connect to the Network:** Ensure you are connected to the corporate VPN or working from a secure company office. Because of our strict security policies, this tool is completely invisible to the outside world.
2. **Access the Portal:** Navigate to the internal web address provided by your IT team (e.g., `http://internal-ai-assistant.company.local`).
3. **Ask a Question:** Type your question into the chat box at the bottom of the screen, just like you would in a normal messaging app.
   * *Example:* "What is our policy on remote work?"
   * *Example:* "What is the process for submitting an IT helpdesk ticket?"
4. **Audit the Sources:** Transparency is key. Underneath every answer the AI gives, you can click **"View Source Documents"** to see the exact paragraphs and files the AI read to formulate its response.

## ⚠️ What This AI *Cannot* Do
* **Search the Public Web:** It cannot look up today's weather, recent news, or general trivia. It is strictly locked down to our internal company documents.
* **Invent Information:** If the answer isn't explicitly written in our internal documents, the AI will respectfully decline to answer.

---

*(Note for IT/Developers: The infrastructure-as-code for this zero-trust AWS deployment—including Terraform network configurations, Lambda backend, Private API Gateway, OpenSearch Serverless, and the Streamlit UI—is contained within the folders of this repository.)*
