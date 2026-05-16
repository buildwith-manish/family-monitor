import { db } from '@/lib/db';
import { NextResponse } from 'next/server';

export async function GET() {
  try {
    const appUsage = await db.appUsage.findMany({
      include: {
        device: {
          include: {
            member: true,
          },
        },
      },
      orderBy: { date: 'desc' },
    });

    return NextResponse.json(appUsage);
  } catch (error) {
    console.error('AppUsage GET error:', error);
    return NextResponse.json({ error: 'Failed to fetch app usage data' }, { status: 500 });
  }
}
