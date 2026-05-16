import { db } from '@/lib/db';
import { NextResponse } from 'next/server';

export async function GET() {
  try {
    const screenTime = await db.screenTime.findMany({
      include: {
        device: {
          include: {
            member: true,
          },
        },
      },
      orderBy: { date: 'desc' },
    });

    return NextResponse.json(screenTime);
  } catch (error) {
    console.error('ScreenTime GET error:', error);
    return NextResponse.json({ error: 'Failed to fetch screen time data' }, { status: 500 });
  }
}

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const { deviceId, limitMinutes, date } = body;

    if (!deviceId || limitMinutes === undefined) {
      return NextResponse.json({ error: 'deviceId and limitMinutes are required' }, { status: 400 });
    }

    const targetDate = date ? new Date(date) : new Date();
    targetDate.setHours(0, 0, 0, 0);

    const screenTime = await db.screenTime.upsert({
      where: {
        deviceId_date: {
          deviceId,
          date: targetDate,
        },
      },
      create: {
        deviceId,
        date: targetDate,
        totalMinutes: 0,
        limitMinutes,
      },
      update: {
        limitMinutes,
      },
    });

    return NextResponse.json(screenTime);
  } catch (error) {
    console.error('ScreenTime POST error:', error);
    return NextResponse.json({ error: 'Failed to set screen time limit' }, { status: 500 });
  }
}
