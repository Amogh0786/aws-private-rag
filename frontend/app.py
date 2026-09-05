import streamlit as st
import requests
import os

# --- Configuration ---
# In a real deployment, this environment variable is injected by your container orchestrator (e.g., ECS)
# It points to the Private API Gateway Endpoint URL created in Phase 4.
API_URL = os.environ.get("API_GATEWAY_URL", "https://your-api-id.execute-api.us-east-1.amazonaws.com/prod/query")

st.set_page_config(page_title="Secure Enterprise Assistant", page_icon="🔐", layout="centered")

st.title("🔐 Secure Enterprise AI Assistant")
st.markdown("""
Welcome to the zero-trust internal knowledge portal. 
Ask questions about company documents. Your prompts and data **never** leave the secure AWS network.
""")

# Initialize chat history
if "messages" not in st.session_state:
    st.session_state.messages = []

# Display chat history on app rerun
for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])

# React to user input
if prompt := st.chat_input("Ask a question about internal policies, architecture, or data..."):
    # Display user message
    st.chat_message("user").markdown(prompt)
    # Add to session state
    st.session_state.messages.append({"role": "user", "content": prompt})

    # Prepare payload for the Private API
    payload = {"query": prompt}
    headers = {"Content-Type": "application/json"}
    
    with st.chat_message("assistant"):
        message_placeholder = st.empty()
        
        try:
            with st.spinner("Securely searching the internal vector database..."):
                # Make the request to the Private API Gateway
                # Note: The server hosting this Streamlit app MUST be inside the VPC to reach the endpoint.
                response = requests.post(API_URL, json=payload, headers=headers, timeout=60)
                response.raise_for_status()
                
                data = response.json()
                answer = data.get("answer", "I could not find an answer to your question.")
                sources = data.get("sources", [])
                
                # Render the AI's response
                message_placeholder.markdown(answer)
                
                # Display the source documents used for the answer
                if sources:
                    with st.expander("View Source Documents"):
                        for i, source in enumerate(sources):
                            st.markdown(f"**Source {i+1}**")
                            st.caption(source.get("page_content", "No content preview available.")[:300] + "...")
                            st.json(source.get("metadata", {}))
                            st.divider()
                
                # Save response to history
                st.session_state.messages.append({"role": "assistant", "content": answer})
                
        except requests.exceptions.ConnectionError:
            error_msg = "❌ Connection Error: Unable to reach the Private API. Ensure this UI is running inside the corporate VPC."
            message_placeholder.error(error_msg)
            st.session_state.messages.append({"role": "assistant", "content": error_msg})
        except requests.exceptions.RequestException as e:
            error_msg = f"❌ Error communicating with the API: {str(e)}"
            message_placeholder.error(error_msg)
            st.session_state.messages.append({"role": "assistant", "content": error_msg})
