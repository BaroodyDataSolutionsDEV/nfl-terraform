import sys
import logging
import psycopg2
import json
import os
import boto3


logger = logging.getLogger()
logger.setLevel(logging.INFO)


try:
    conn = psycopg2.connect(host=os.environ['RDS_HOST'], user=os.environ['RDS_ETL_USER'], password=os.environ['RDS_ETL_PASS'], dbname=os.environ['RDS_DB_NAME'], port=os.environ['RDS_PORT'])
except psycopg2.Error as e:
    logger.error("Error connecting to postgres instance: {e}")
    raise e

logger.info("Connection to RDS Postgres instance succeeded")


def refresh_data_from_s3(cur):
    try: 
        logger.info("Loading pbp data..")
        cur.execute("select aws_s3.table_import_from_s3('raw.pbp', '', '(format csv)', aws_commons.create_s3_uri('s3-test-bucket-ct', 'updates/pbp/20241112_play_by_play_2024.csv', 'us-east-1'))")
        
        logger.info("Loading injuries data..")
        cur.execute("select aws_s3.table_import_from_s3('raw.injuries', '', '(format csv)', aws_commons.create_s3_uri('s3-test-bucket-ct', 'updates/injuries/20241112_injuries_2024.csv', 'us-east-1'))")
        
        logger.info("Loading rosters data..")
        cur.execute("select aws_s3.table_import_from_s3('raw.rosters', '', '(format csv)', aws_commons.create_s3_uri('s3-test-bucket-ct', 'updates/rosters/20241112_roster_2024.csv', 'us-east-1'))")
        
        logger.info("Loading advstats_def data..")
        cur.execute("select aws_s3.table_import_from_s3('raw.advstats_def', '', '(format csv)', aws_commons.create_s3_uri('s3-test-bucket-ct', 'updates/advstats/20241112_advstats_week_def_2024.csv', 'us-east-1'))")
        
        logger.info("Loading advstats_rush data..")
        cur.execute("select aws_s3.table_import_from_s3('raw.advstats_rush', '', '(format csv)', aws_commons.create_s3_uri('s3-test-bucket-ct', 'updates/advstats/20241112_advstats_week_rush_2024.csv', 'us-east-1'))")
        
        logger.info("Loading advstats_rec data..")
        cur.execute("select aws_s3.table_import_from_s3('raw.advstats_rec', '', '(format csv)', aws_commons.create_s3_uri('s3-test-bucket-ct', 'updates/advstats/20241112_advstats_week_rec_2024.csv', 'us-east-1'))")
        
        logger.info("Loading advstats_pass data..")
        cur.execute("select aws_s3.table_import_from_s3('raw.advstats_pass', '', '(format csv)', aws_commons.create_s3_uri('s3-test-bucket-ct', 'updates/advstats/20241112_advstats_week_pass_2024.csv', 'us-east-1'))")
    except psycopg2.Error as e:
        logger.error("Error running refresh queries: {e}")
        raise e

def lambda_handler(event, context):
    try:
        with conn.cursor() as cur:
            logger.info("Refreshing raw tables")
            refresh_data_from_s3(cur)
        conn.commit()

        logger.info(f"Refresh complete")
        return {
            'statusCode': 200,
            'body': json.dumps('Lambda function executed successfully!')
        }
    except Exception as e:
        logger.error(f"Error in lambda_handler: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }