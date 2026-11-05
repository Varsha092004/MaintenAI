
import os
from pathlib import Path

from dotenv import load_dotenv
from langchain_community.document_loaders import PyPDFLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_openai import OpenAIEmbeddings, ChatOpenAI
from langchain_community.vectorstores import FAISS

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")

PDF_PATH = BASE_DIR.parent / "docs" / "maintenance_manual.pdf"
VECTOR_PATH = BASE_DIR / "faiss_index"

vector_store = None


def create_vector_store():
    global vector_store

    if not os.getenv("OPENAI_API_KEY"):
        raise ValueError("OpenAI API key is missing in .env file.")

    if VECTOR_PATH.exists():
        embeddings = OpenAIEmbeddings(
            model="text-embedding-3-small"
        )
        vector_store = FAISS.load_local(
            str(VECTOR_PATH),
            embeddings,
            allow_dangerous_deserialization=True
        )
        return vector_store

    if not PDF_PATH.exists():
        raise FileNotFoundError(
            f"Maintenance PDF not found: {PDF_PATH}"
        )

    loader = PyPDFLoader(str(PDF_PATH))
    documents = loader.load()

    splitter = RecursiveCharacterTextSplitter(
        chunk_size=1000,
        chunk_overlap=200
    )
    chunks = splitter.split_documents(documents)

    embeddings = OpenAIEmbeddings(
        model="text-embedding-3-small"
    )

    vector_store = FAISS.from_documents(chunks, embeddings)
    vector_store.save_local(str(VECTOR_PATH))

    return vector_store


def ask_maintenance_question(question, machine_analysis=None):
    global vector_store

    if vector_store is None:
        create_vector_store()

    retriever = vector_store.as_retriever(
        search_kwargs={"k": 4}
    )

    retrieved_docs = retriever.invoke(question)

    context = "\n\n".join(
        doc.page_content for doc in retrieved_docs
    )

    if machine_analysis is not None:
        prediction = machine_analysis["prediction"]
        probability = machine_analysis["probability"]

        if prediction == 1:
            situation = """
            IMPORTANT: The Machine Learning model has PREDICTED A
            POSSIBLE MACHINE FAILURE.

            Start your answer with a clear failure warning.
            Explain that the model has flagged the machine as at risk.
            Discuss the supplied sensor readings and failure probability.
            Give relevant maintenance guidance only when supported by
            the retrieved manual.
            Clearly state that the exact failure type is not identified
            by this binary prediction model.
            """
        else:
            situation = """
            IMPORTANT: The Machine Learning model has NOT PREDICTED
            A MACHINE FAILURE for these readings.

            Start by stating that no failure is currently predicted.
            Explain that this is not a guarantee that the machine is
            completely safe or free from faults.
            Discuss the supplied sensor readings and probability.
            Recommend routine monitoring and only give maintenance
            guidance supported by the retrieved manual.
            """

        machine_context = f"""
        MACHINE ANALYSIS:
        Machine ID: {machine_analysis['machine_id']}
        Machine Type: {machine_analysis['machine_type']}
        Air Temperature: {machine_analysis['air_temperature']} K
        Process Temperature: {machine_analysis['process_temperature']} K
        Rotational Speed: {machine_analysis['rotational_speed']} rpm
        Torque: {machine_analysis['torque']} Nm
        Tool Wear: {machine_analysis['tool_wear']} minutes

        ML Prediction: {
            "FAILURE PREDICTED" if prediction == 1
            else "NO FAILURE PREDICTED"
        }
        Failure Probability: {probability:.2f} percent

        {situation}
        """
    else:
        machine_context = """
        This is a general maintenance question.
        Answer using the retrieved maintenance manual.
        """

    llm = ChatOpenAI(
        model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
        temperature=0
    )

    prompt = f"""
    You are MaintenAI, an industrial predictive maintenance assistant.

    Your job is to explain machine conditions clearly and safely.

    {machine_context}

    MAINTENANCE MANUAL CONTEXT:
    {context}

    USER QUESTION:
    {question}

    IMPORTANT RULES:
    1. Clearly distinguish the ML model's prediction from facts in
       the maintenance manual.
    2. Do not invent fault causes, thresholds, or repair procedures.
    3. If the manual does not contain enough information, say so.
    4. Never describe a healthy prediction as a confirmed failure.
    5. Never describe a failure prediction as a confirmed physical fault.
    6. Include useful safety precautions only when supported by
       the manual.
    7. Explain the result in simple language.

    Structure the response with:
    - Machine condition
    - Explanation of the ML result
    - Relevant manual information
    - Recommended next steps
    - Safety precautions and limitations
    """

    response = llm.invoke(prompt)

    sources = []

    for doc in retrieved_docs:
        sources.append({
            "page": doc.metadata.get("page", "Unknown"),
            "source": Path(
                doc.metadata.get("source", "Unknown")
            ).name
        })

    return {
        "answer": response.content,
        "sources": sources
    }
