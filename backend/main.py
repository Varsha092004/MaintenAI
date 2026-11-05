
import os
import joblib
import pandas as pd

from datetime import datetime, timezone
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from rag_engine import ask_maintenance_question

app = FastAPI(
    title="MaintenAI",
    description="Intelligent Predictive Maintenance System with LLM and RAG",
    version="1.1.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"]
)

# Load trained ML model
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_PATH = os.path.join(BASE_DIR, "models", "failure_model.pkl")

model = joblib.load(MODEL_PATH)


# Machine sensor input format
class MachineInput(BaseModel):
    machine_id: str = "MACHINE-001"
    machine_type: str
    air_temperature: float
    process_temperature: float
    rotational_speed: float
    torque: float
    tool_wear: float


# RAG chat input format
class ChatInput(BaseModel):
    question: str


@app.get("/")
def home():
    return {
        "message": "Welcome to MaintenAI",
        "status": "Backend running successfully"
    }


@app.get("/health")
def health_check():
    return {
        "status": "healthy",
        "project": "MaintenAI"
    }


@app.get("/machine/sample")
def get_machine_data():
    return {
        "machine_id": "MACHINE-001",
        "machine_name": "Industrial Motor",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "sensors": {
            "air_temperature": 298.1,
            "process_temperature": 308.6,
            "rotational_speed": 1500,
            "torque": 40.0,
            "tool_wear": 120
        },
        "status": "Monitoring"
    }


# Machine failure prediction API
@app.post("/predict")
def predict_failure(data: MachineInput):
    try:
        input_data = pd.DataFrame([{
            "Type": data.machine_type,
            "Air temperature [K]": data.air_temperature,
            "Process temperature [K]": data.process_temperature,
            "Rotational speed [rpm]": data.rotational_speed,
            "Torque [Nm]": data.torque,
            "Tool wear [min]": data.tool_wear
        }])

        prediction = int(model.predict(input_data)[0])
        probability = float(model.predict_proba(input_data)[0][1])

        return {
            "machine_id": data.machine_id,
            "prediction": prediction,
            "result": (
                "Machine Failure Predicted"
                if prediction == 1
                else "No Failure Predicted"
            ),
            "failure_probability": round(probability * 100, 2),
            "timestamp": datetime.now(timezone.utc).isoformat()
        }

    except Exception as error:
        raise HTTPException(
            status_code=500,
            detail=str(error)
        )


# LLM + RAG maintenance assistant API
@app.post("/chat")
def maintenance_chat(data: ChatInput):
    try:
        result = ask_maintenance_question(data.question)

        return {
            "question": data.question,
            "answer": result["answer"],
            "sources": result["sources"],
            "timestamp": datetime.now(timezone.utc).isoformat()
        }

    except Exception as error:
        raise HTTPException(
            status_code=500,
            detail=str(error)
        )

# Combined ML + LLM + RAG Analysis API
# Combined ML + LLM + RAG Analysis API
@app.post("/analyze")
def analyze_machine(data: MachineInput):
    try:
        # Step 1: Prepare machine sensor data
        input_data = pd.DataFrame([{
            "Type": data.machine_type,
            "Air temperature [K]": data.air_temperature,
            "Process temperature [K]": data.process_temperature,
            "Rotational speed [rpm]": data.rotational_speed,
            "Torque [Nm]": data.torque,
            "Tool wear [min]": data.tool_wear
        }])

        # Step 2: Predict machine failure using ML
        prediction = int(model.predict(input_data)[0])
        probability = float(model.predict_proba(input_data)[0][1])

        status = (
            "Machine Failure Predicted"
            if prediction == 1
            else "No Failure Predicted"
        )

        # Step 3: Prepare machine analysis question
        question = f"""
        Analyze this industrial machine using the maintenance manual.

        Machine ID: {data.machine_id}
        Machine Type: {data.machine_type}
        Air Temperature: {data.air_temperature} K
        Process Temperature: {data.process_temperature} K
        Rotational Speed: {data.rotational_speed} rpm
        Torque: {data.torque} Nm
        Tool Wear: {data.tool_wear} minutes

        ML Prediction: {status}
        Failure Probability: {probability * 100:.2f} percent

        Explain the prediction and recommend maintenance actions
        based only on the retrieved manual.
        Mention if the manual lacks sufficient information.
        Include safety precautions.
        """

        # Step 4: Send ML result and sensor readings to RAG + LLM
        analysis = ask_maintenance_question(
            question,
            machine_analysis={
                "machine_id": data.machine_id,
                "machine_type": data.machine_type,
                "air_temperature": data.air_temperature,
                "process_temperature": data.process_temperature,
                "rotational_speed": data.rotational_speed,
                "torque": data.torque,
                "tool_wear": data.tool_wear,
                "prediction": prediction,
                "probability": probability * 100
            }
        )

        # Step 5: Return complete analysis
        return {
            "machine_id": data.machine_id,
            "ml_prediction": status,
            "failure_probability": round(probability * 100, 2),
            "llm_rag_analysis": analysis["answer"],
            "sources": analysis["sources"],
            "timestamp": datetime.now(timezone.utc).isoformat()
        }

    except Exception as error:
        raise HTTPException(
            status_code=500,
            detail=str(error)
        )
